//
//  HackerRankToolProvider.swift
//  HackerRankMCP
//

import Foundation
import HackerRankKit
import MCP
import MCPKit

// Tool dispatch is intentionally centralized so capability registration and routing cannot drift.
// swiftlint:disable file_length

/// The outcome of a bounded search: the matches plus how much of the collection was scanned.
private struct SearchHits<Item> {
    let matches: [Item]
    let scanned: Int
    let truncated: Bool
    let nextCursor: String?
}

// Complete shared HackerRank tools with live host account and client injection.
// swiftlint:disable:next type_body_length
public struct HackerRankToolProvider: MCPToolProvider {
    private let context: @Sendable @MainActor () -> HackerRankMCPContext
    private let makeClient: @Sendable (HackerRankMCPAccount) async throws -> HackerRankClient
    let allowWrites: Bool
    let writeDisabledMessage: String

    /// Embeds the complete tool implementation using the host's current account snapshot.
    public init(
        allowWrites: Bool = false,
        writeDisabledMessage: String = "Write tools are disabled.",
        context: @escaping @Sendable @MainActor () -> HackerRankMCPContext,
        makeClient: @escaping @Sendable (HackerRankMCPAccount) async throws -> HackerRankClient
    ) {
        self.allowWrites = allowWrites
        self.writeDisabledMessage = writeDisabledMessage
        self.context = context
        self.makeClient = makeClient
    }

    func client(for account: HackerRankMCPAccount) async throws -> HackerRankClient {
        try await makeClient(account)
    }

    public func tools() async -> [Tool] {
        // Read tools are always advertised; write tools only when the user has opted in (#73).
        mcpTools(from: Self.descriptors + Self.additionalReadDescriptors + (allowWrites ? Self.writeDescriptors : []))
    }

    public func callTool(_ name: String, arguments: [String: Value]?) async -> CallTool.Result {
        let account: String? = if case let .string(value)? = arguments?["account"] {
            value
        } else {
            nil
        }
        let accountHasWrongType = arguments?["account"] != nil && account == nil
        let accountError = accountHasWrongType ? nil : await accountResolutionError(account)
        return if !Self.isKnownTool(name) {
            errorResult("Unknown tool: \(name)")
        } else if let unknown = Self.unknownArgument(in: arguments, toolName: name) {
            errorResult("Unknown argument “\(unknown)” for tool \(name).")
        } else if let wrongBoolean = Self.wrongTypedBooleanArgument(in: arguments, toolName: name) {
            errorResult("`\(wrongBoolean)` must be a boolean.")
        } else if let wrongInteger = Self.wrongTypedIntegerArgument(in: arguments, toolName: name) {
            errorResult("`\(wrongInteger)` must be an integer.")
        } else if accountHasWrongType {
            errorResult("`account` must be a string.")
        } else if let accountError {
            errorResult(accountError)
        } else {
            await dispatchTool(name, arguments: arguments, account: account)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func dispatchTool(
        _ name: String,
        arguments: [String: Value]?,
        account: String?
    ) async -> CallTool.Result {
        if name.hasPrefix("api_") {
            return await callFullAPI(name, arguments: arguments, account: account)
        }
        // Write tools are gated behind the separate opt-in even if a client calls one by name
        // while it isn't advertised (#73).
        if Self.isWriteTool(name) {
            guard allowWrites else {
                return errorResult(writeDisabledMessage)
            }

            return await callWriteTool(name, arguments: arguments, account: account)
        }

        if let operation = HackerRankProvider.readOperations.first(where: { $0.name == name }),
           !Self.descriptors.contains(where: { $0["name"] as? String == name }) {
            return await callRead(operation, arguments: arguments, account: account)
        }
        switch name {
        case "list_accounts": return await listAccounts()

        case "list_tests":
            let cursor = Self.normalizedOptionalString(stringArgument(arguments, "cursor"))
            guard arguments?["cursor"] == nil || cursor != nil else {
                return errorResult("`cursor` must not be empty.")
            }

            return await listTests(cursor: cursor, account: account)

        case "list_questions":
            let cursor = Self.normalizedOptionalString(stringArgument(arguments, "cursor"))
            guard arguments?["cursor"] == nil || cursor != nil else {
                return errorResult("`cursor` must not be empty.")
            }

            return await listQuestions(cursor: cursor, account: account)

        case "list_interviews":
            let cursor = Self.normalizedOptionalString(stringArgument(arguments, "cursor"))
            guard arguments?["cursor"] == nil || cursor != nil else {
                return errorResult("`cursor` must not be empty.")
            }

            return await listInterviews(cursor: cursor, account: account)

        case "list_users", "list_teams":
            // Org enumeration (#9), in its own dispatch + file.
            return await callOrgListTool(name, arguments: arguments, account: account)

        case "list_candidates", "candidate_report_pdf", "get_invite_template", "get_interview_template",
             "search_tests", "search_questions", "search_interviews":
            return await callKeyedTool(name, arguments: arguments, account: account)

        case "list_invite_templates", "list_interview_templates":
            return await callTemplateTool(name, arguments: arguments, account: account)

        case "search_users", "search_candidates":
            // Server-side people/candidate search (#104), in its own dispatch + file.
            return await callPeopleSearchTool(name, arguments: arguments, account: account)

        default:
            return errorResult("Unknown tool: \(name)")
        }
    }

    static func isKnownTool(_ name: String) -> Bool {
        (descriptors + writeDescriptors + additionalReadDescriptors).contains {
            $0["name"] as? String == name
        }
    }

    static func unknownArgument(in arguments: [String: Value]?, toolName: String) -> String? {
        guard let arguments else { return nil }

        let descriptor = (descriptors + writeDescriptors + additionalReadDescriptors).first {
            $0["name"] as? String == toolName
        }
        let schema = descriptor?["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        let allowed = Set(properties?.keys.map(\.self) ?? [])
        return arguments.keys.sorted().first { !allowed.contains($0) }
    }

    static func wrongTypedBooleanArgument(in arguments: [String: Value]?, toolName: String) -> String? {
        guard let arguments else { return nil }

        let descriptor = (descriptors + writeDescriptors + additionalReadDescriptors).first {
            $0["name"] as? String == toolName
        }
        let schema = descriptor?["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        return arguments.keys.sorted().first { key in
            guard let property = properties?[key] as? [String: Any],
                  property["type"] as? String == "boolean" else { return false }
            guard case .bool = arguments[key] else { return true }

            return false
        }
    }

    static func wrongTypedIntegerArgument(in arguments: [String: Value]?, toolName: String) -> String? {
        guard let arguments else { return nil }

        let descriptor = (descriptors + writeDescriptors + additionalReadDescriptors).first {
            $0["name"] as? String == toolName
        }
        let schema = descriptor?["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        return arguments.keys.sorted().first { key in
            guard let property = properties?[key] as? [String: Any],
                  property["type"] as? String == "integer" else { return false }
            guard case .int = arguments[key] else { return true }

            return false
        }
    }

    static func normalizedSearchQuery(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validatedSearchQuery(_ value: String) -> String? {
        let normalized = normalizedSearchQuery(value)
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated static func candidateReportURL(primary: String?, fallback: String?) -> String? {
        [primary, fallback]
            .compactMap { $0.flatMap(remoteWebURL(from:))?.absoluteString }
            .first
    }

    nonisolated static func validatedPositiveID(_ id: Int?) -> Int? {
        guard let id, id > 0 else { return nil }

        return id
    }

    nonisolated static func allResourceIDsUsable(_ ids: [String]) -> Bool {
        ids.allSatisfy { validatedCreatedID($0) != nil }
    }

    nonisolated static func inviteTemplatePayload(_ template: InviteTemplate) -> [String: String]? {
        guard let id = validatedCreatedID(template.id) else { return nil }

        return [
            "id": id,
            "name": template.name ?? "",
            "subject": template.subject ?? "",
            "content": template.content ?? ""
        ]
    }

    nonisolated static func interviewTemplatePayload(_ template: InterviewTemplate) -> [String: Any]? {
        guard let id = validatedPositiveID(template.id) else { return nil }

        return [
            "id": id,
            "name": template.name ?? "",
            "status": template.status ?? NSNull(),
            "created_at": template.createdAt ?? "",
            "roles": template.roles ?? [],
            "team_share": template.teamShare ?? NSNull(),
            "questions": template.questions ?? [],
            "scorecard": template.scorecard ?? NSNull()
        ] as [String: Any]
    }

    private func invalidSearchQuery() -> CallTool.Result {
        errorResult("`query` must contain non-whitespace text.")
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func callKeyedTool(_ name: String, arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        switch name {
        case "list_candidates":
            guard let rawTestID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
            guard let testID = Self.normalizedOptionalString(rawTestID) else {
                return errorResult("`test_id` must not be empty.")
            }

            let cursor = Self.normalizedOptionalString(stringArgument(arguments, "cursor"))
            guard arguments?["cursor"] == nil || cursor != nil else {
                return errorResult("`cursor` must not be empty.")
            }

            return await listCandidates(
                testID: testID,
                cursor: cursor,
                account: account
            )

        case "candidate_report_pdf":
            guard let rawTestID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
            guard let testID = Self.normalizedOptionalString(rawTestID) else {
                return errorResult("`test_id` must not be empty.")
            }
            guard let rawCandidateID = stringArgument(arguments, "candidate_id") else {
                return missingArgument("candidate_id")
            }
            guard let candidateID = Self.normalizedOptionalString(rawCandidateID) else {
                return errorResult("`candidate_id` must not be empty.")
            }

            return await candidateReportPDF(testID: testID, candidateID: candidateID, account: account)

        case "get_invite_template":
            guard let rawTemplateID = stringArgument(arguments, "template_id") else {
                return missingArgument("template_id")
            }
            guard let templateID = Self.normalizedOptionalString(rawTemplateID) else {
                return errorResult("`template_id` must not be empty.")
            }

            return await getInviteTemplate(templateID: templateID, account: account)

        case "get_interview_template":
            guard case let .int(templateID)? = arguments?["template_id"] else {
                return missingArgument("template_id")
            }
            guard templateID > 0 else {
                return errorResult("`template_id` must be greater than zero.")
            }

            return await getInterviewTemplate(templateID: templateID, account: account)

        case "search_tests":
            guard let rawQuery = stringArgument(arguments, "query") else { return missingArgument("query") }
            guard let query = Self.validatedSearchQuery(rawQuery) else { return invalidSearchQuery() }

            let cursor = Self.normalizedOptionalString(stringArgument(arguments, "cursor"))
            guard arguments?["cursor"] == nil || cursor != nil else {
                return errorResult("`cursor` must not be empty.")
            }

            return await searchTests(query: query, cursor: cursor, account: account)

        case "search_questions":
            guard let rawQuery = stringArgument(arguments, "query") else { return missingArgument("query") }
            guard let query = Self.validatedSearchQuery(rawQuery) else { return invalidSearchQuery() }

            let cursor = Self.normalizedOptionalString(stringArgument(arguments, "cursor"))
            guard arguments?["cursor"] == nil || cursor != nil else {
                return errorResult("`cursor` must not be empty.")
            }

            return await searchQuestions(query: query, cursor: cursor, account: account)

        case "search_interviews":
            guard let rawQuery = stringArgument(arguments, "query") else { return missingArgument("query") }
            guard let query = Self.validatedSearchQuery(rawQuery) else { return invalidSearchQuery() }

            let cursor = Self.normalizedOptionalString(stringArgument(arguments, "cursor"))
            guard arguments?["cursor"] == nil || cursor != nil else {
                return errorResult("`cursor` must not be empty.")
            }

            return await searchInterviews(query: query, cursor: cursor, account: account)

        default:
            return errorResult("Unknown tool: \(name)")
        }
    }

    private func callTemplateTool(
        _ name: String,
        arguments: [String: Value]?,
        account: String?
    ) async -> CallTool.Result {
        switch name {
        case "list_invite_templates":
            let access = Self.normalizedOptionalString(stringArgument(arguments, "access"))?.lowercased()
            guard access.map({ ["company", "private"].contains($0) }) ?? true else {
                return errorResult("`access` must be company or private.")
            }

            let cursor = Self.normalizedOptionalString(stringArgument(arguments, "cursor"))
            guard arguments?["cursor"] == nil || cursor != nil else {
                return errorResult("`cursor` must not be empty.")
            }

            return await listInviteTemplates(cursor: cursor, access: access, account: account)

        case "list_interview_templates":
            let cursor = Self.normalizedOptionalString(stringArgument(arguments, "cursor"))
            guard arguments?["cursor"] == nil || cursor != nil else {
                return errorResult("`cursor` must not be empty.")
            }

            return await listInterviewTemplates(cursor: cursor, account: account)

        default:
            return errorResult("Unknown tool: \(name)")
        }
    }

    // MARK: - Account resolution

    /// The account matching `identifier` (label or UUID), or the current account when omitted.
    /// An explicit unknown identifier fails closed so writes can never drift to another org.
    /// Internal (not private) so the write-tools extension in another file can resolve too (#73).
    @MainActor
    public func resolveAccount(_ identifier: String?) -> HackerRankMCPAccount? {
        let store = context()
        guard let identifier else { return store.currentAccount }

        if let id = UUID(uuidString: identifier) {
            return store.accounts.first { $0.id == id }
        }
        let matches = store.accounts.filter { $0.label == identifier }
        return matches.count == 1 ? matches[0] : nil
    }

    @MainActor
    private func accountResolutionError(_ identifier: String?) -> String? {
        guard let identifier, UUID(uuidString: identifier) == nil else { return nil }

        let matches = context().accounts.filter { $0.label == identifier }
        guard matches.count > 1 else { return nil }

        return "Account label `\(identifier)` is ambiguous. Use an account UUID from `list_accounts`."
    }

    // MARK: - List tools

    @MainActor
    private func listAccounts() -> CallTool.Result {
        jsonResult(accountsPayload())
    }

    func pageMetadata(_ page: Page<some Sendable>) -> [String: Any] {
        var metadata: [String: Any] = [
            "returned_count": page.items.count,
            "has_more": page.next != nil
        ]
        if let totalCount = page.totalCount {
            metadata["total_count"] = totalCount
        }
        return metadata
    }

    nonisolated static func candidatePayload(_ candidate: TestCandidate) -> [String: Any]? {
        guard let id = validatedCreatedID(candidate.id) else { return nil }

        return [
            "id": id,
            "email": candidate.email,
            "name": candidate.fullName ?? "",
            "score": candidate.score.map { $0 as Any } ?? NSNull(),
            "score_available": candidate.score != nil,
            "status": candidateStatusLabel(candidate.status, atsState: candidate.atsState) ?? ""
        ]
    }

    @MainActor
    private func listTests(cursor: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await (client(for: resolved)).testsPage(after: cursor)
            guard Self.allResourceIDsUsable(page.items.map(\.id)) else {
                return errorResult("HackerRank returned a test without a usable ID.")
            }

            let items = page.items.map {
                ["id": $0.id.trimmingCharacters(in: .whitespacesAndNewlines),
                 "name": $0.name, "state": $0.state ?? ""]
            }
            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "tests": items,
                "next_cursor": page.next ?? NSNull()
            ]) { _, value in value })
        } catch {
            return errorResult("Couldn't list tests: \(toolErrorMessage(error))")
        }
    }

    @MainActor
    private func listQuestions(cursor: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await (client(for: resolved)).questionsPage(after: cursor)
            guard Self.allResourceIDsUsable(page.items.map(\.id)) else {
                return errorResult("HackerRank returned a question without a usable ID.")
            }

            let items = page.items.map {
                ["id": $0.id.trimmingCharacters(in: .whitespacesAndNewlines),
                 "name": $0.name, "type": $0.type]
            }
            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "questions": items,
                "next_cursor": page.next ?? NSNull()
            ]) { _, value in value })
        } catch {
            return errorResult("Couldn't list questions: \(toolErrorMessage(error))")
        }
    }

    @MainActor
    private func listInterviews(cursor: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await (client(for: resolved)).interviewsPage(after: cursor)
            guard Self.allResourceIDsUsable(page.items.map(\.id)) else {
                return errorResult("HackerRank returned an interview without a usable ID.")
            }

            let items = page.items.map {
                ["id": $0.id.trimmingCharacters(in: .whitespacesAndNewlines),
                 "title": $0.title ?? "", "status": $0.status]
            }
            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "interviews": items,
                "next_cursor": page.next ?? NSNull()
            ]) { _, value in value })
        } catch {
            return errorResult("Couldn't list interviews: \(toolErrorMessage(error))")
        }
    }

    @MainActor
    private func listCandidates(testID: String, cursor: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await (client(for: resolved)).candidatesPage(
                testID: testID,
                after: cursor
            )
            let items = page.items.compactMap(Self.candidatePayload)
            guard items.count == page.items.count else {
                return errorResult("HackerRank returned a candidate without a usable ID.")
            }

            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "test_id": testID, "candidates": items,
                "next_cursor": page.next ?? NSNull()
            ]) { _, value in value })
        } catch {
            return errorResult("Couldn't list candidates: \(toolErrorMessage(error))")
        }
    }

    @MainActor
    private func candidateReportPDF(testID: String, candidateID: String, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let pdf = try await (client(for: resolved)).candidateReportPDF(
                testID: testID,
                candidateID: candidateID
            )
            guard let url = Self.candidateReportURL(primary: pdf.url, fallback: pdf.pdfURL) else {
                return errorResult("HackerRank returned no usable candidate report PDF URL.")
            }

            return jsonResult([
                "account": resolved.label,
                "test_id": testID,
                "candidate_id": candidateID,
                "url": url
            ])
        } catch {
            return errorResult("Couldn't fetch candidate report PDF: \(toolErrorMessage(error))")
        }
    }

    @MainActor
    private func listInviteTemplates(cursor: String?, access: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await (client(for: resolved)).inviteTemplatesPage(
                after: cursor, access: access
            )
            let items = page.items.compactMap(Self.inviteTemplatePayload)
            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "templates": items,
                "next_cursor": page.next ?? NSNull()
            ]) { _, value in value })
        } catch {
            return errorResult("Couldn't list invite templates: \(toolErrorMessage(error))")
        }
    }

    @MainActor
    private func getInviteTemplate(templateID: String, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let template = try await (client(for: resolved)).inviteTemplate(id: templateID)
            guard let responseID = Self.validatedCreatedID(template.id) else {
                return errorResult("HackerRank returned an invite template without a usable ID.")
            }

            return jsonResult([
                "account": resolved.label,
                "template": [
                    "id": responseID,
                    "name": template.name ?? "",
                    "subject": template.subject ?? "",
                    "content": template.content ?? ""
                ]
            ])
        } catch {
            return errorResult("Couldn't get invite template: \(toolErrorMessage(error))")
        }
    }

    @MainActor
    private func listInterviewTemplates(cursor: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await (client(for: resolved)).interviewTemplatesPage(after: cursor)
            let items = page.items.compactMap(Self.interviewTemplatePayload)
            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "templates": items,
                "next_cursor": page.next ?? NSNull()
            ]) { _, value in value })
        } catch {
            return errorResult("Couldn't list interview templates: \(toolErrorMessage(error))")
        }
    }

    @MainActor
    private func getInterviewTemplate(templateID: Int, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let template = try await (client(for: resolved)).interviewTemplate(id: templateID)
            guard let responseID = Self.validatedPositiveID(template.id) else {
                return errorResult("HackerRank returned an interview template without a usable ID.")
            }

            return jsonResult([
                "account": resolved.label,
                "template": [
                    "id": responseID,
                    "name": template.name ?? "",
                    "status": template.status ?? NSNull(),
                    "created_at": template.createdAt ?? "",
                    "roles": template.roles ?? [],
                    "team_share": template.teamShare ?? NSNull(),
                    "questions": template.questions ?? [],
                    "scorecard": template.scorecard ?? NSNull()
                ] as [String: Any]
            ])
        } catch {
            return errorResult("Couldn't get interview template: \(toolErrorMessage(error))")
        }
    }

    // MARK: - Account payloads

    @MainActor
    func accountsPayload() -> [String: Any] {
        let store = context()
        let merged = store.isMergedView
        let accounts = store.accounts.map { account in
            [
                "id": account.id.uuidString,
                "label": account.label,
                "current": !merged && account.id == store.currentAccountID
            ] as [String: Any]
        }
        return [
            "accounts": accounts,
            "total_count": accounts.count,
            "scope": merged ? "all_accounts" : "current_account"
        ]
    }
}

// MARK: - Search

nonisolated struct BoundedSearchPage<Item> {
    let items: [Item]
    let scanned: Int
    let next: String?
}

nonisolated struct BoundedSearchProgress<ID: Hashable> {
    private var seenIDs: Set<ID> = []
    private var seenCursors: Set<String> = []

    init(initialCursor: String? = nil) {
        if let initialCursor {
            seenCursors.insert(initialCursor)
        }
    }

    mutating func accept<Item>(
        _ items: [Item],
        next: String?,
        id: (Item) -> ID
    ) -> BoundedSearchPage<Item> {
        let unique = items.filter { seenIDs.insert(id($0)).inserted }
        guard let next, seenCursors.insert(next).inserted else {
            return BoundedSearchPage(items: unique, scanned: items.count, next: nil)
        }

        return BoundedSearchPage(items: unique, scanned: items.count, next: next)
    }
}

extension HackerRankToolProvider {
    /// Pages through up to `maxPages` of a collection, returning the items whose `text` contains
    /// the query (case-insensitive). Bounded so a search never drains a huge live collection;
    /// reports how many were scanned and whether more pages remain unseen.
    @MainActor
    private func search<Item>(
        query: String,
        cursor startCursor: String?,
        maxPages: Int = 5,
        page: @MainActor (_ cursor: String?) async throws -> Page<Item>,
        id: (Item) -> String,
        text: (Item) -> String
    ) async throws -> SearchHits<Item> {
        var cursor = startCursor
        var scanned = 0
        var matches: [Item] = []
        var pages = 0
        var progress = BoundedSearchProgress<String>(initialCursor: startCursor)
        repeat {
            let result = try await page(cursor)
            let accepted = progress.accept(result.items, next: result.next, id: id)
            scanned += accepted.scanned
            matches += accepted.items.filter { text($0).localizedCaseInsensitiveContains(query) }
            cursor = accepted.next
            pages += 1
        } while cursor != nil && pages < maxPages
        return SearchHits(matches: matches, scanned: scanned, truncated: cursor != nil, nextCursor: cursor)
    }

    @MainActor
    private func searchTests(query: String, cursor: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let client = try await (client(for: resolved))
            let hits = try await search(
                query: query,
                cursor: cursor,
                page: { try await client.testsPage(after: $0) },
                id: \.id,
                text: { $0.name }
            )
            let items = hits.matches.map { ["id": $0.id, "name": $0.name, "state": $0.state ?? ""] }
            return searchResult(account: resolved, query: query, items: items, hits: hits, key: "matches")
        } catch {
            return errorResult("Couldn't search tests: \(toolErrorMessage(error))")
        }
    }

    @MainActor
    private func searchQuestions(query: String, cursor: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let client = try await (client(for: resolved))
            let hits = try await search(
                query: query,
                cursor: cursor,
                page: { try await client.questionsPage(after: $0) },
                id: \.id,
                text: { $0.name }
            )
            let items = hits.matches.map { ["id": $0.id, "name": $0.name, "type": $0.type] }
            return searchResult(account: resolved, query: query, items: items, hits: hits, key: "matches")
        } catch {
            return errorResult("Couldn't search questions: \(toolErrorMessage(error))")
        }
    }

    @MainActor
    private func searchInterviews(query: String, cursor: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let client = try await (client(for: resolved))
            let hits = try await search(
                query: query,
                cursor: cursor,
                page: { try await client.interviewsPage(after: $0) },
                id: \.id,
                text: { "\($0.title ?? "") \($0.status)" }
            )
            let items = hits.matches.map { ["id": $0.id, "title": $0.title ?? "", "status": $0.status] }
            return searchResult(account: resolved, query: query, items: items, hits: hits, key: "matches")
        } catch {
            return errorResult("Couldn't search interviews: \(toolErrorMessage(error))")
        }
    }

    private func searchResult(
        account: HackerRankMCPAccount,
        query: String,
        items: [[String: Any]],
        hits: SearchHits<some Any>,
        key: String
    ) -> CallTool.Result {
        jsonResult([
            "account": account.label, "query": query, key: items,
            "count": items.count, "scanned": hits.scanned, "truncated": hits.truncated,
            "next_cursor": hits.nextCursor ?? NSNull()
        ])
    }
}
