import Foundation
import HackerRankKit
import MCP
import MCPKit

private final class HackerRankClientCache: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var storage: [UUID: HackerRankClient] = [:]

    func client(for account: HackerRankMCPAccount) async -> HackerRankClient {
        if let existing = synced({ storage[account.id] }) {
            return existing
        }
        let created = await HackerRankClient(token: account.token, baseURL: account.baseURL)
        return synced {
            if let existing = storage[account.id] {
                return existing
            }
            storage[account.id] = created
            return created
        }
    }

    private func synced<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

public struct HackerRankProvider: MCPToolProvider {
    public let accountSet: HackerRankMCPAccountSet
    private let clientCache = HackerRankClientCache()

    public init(accountSet: HackerRankMCPAccountSet) {
        self.accountSet = accountSet
    }

    public func tools() async -> [Tool] {
        mcpTools(from: Self.descriptors)
    }

    public func callTool(_ name: String, arguments: [String: Value]?) async -> CallTool.Result {
        guard Self.names.contains(name) else { return errorResult("Unknown tool: \(name)") }

        if let unexpected = unexpectedArguments(for: name, in: arguments) {
            return errorResult("Unexpected argument(s): \(unexpected)")
        }

        // list_accounts is config-local: it must not resolve an account argument.
        if name == "list_accounts" {
            return compactJSONResult(["accounts": accountSet.accounts.map {
                ["id": $0.id.uuidString, "name": $0.name, "base_url": $0.baseURL.absoluteString]
            }])
        }

        let accountArg = typedStringArgument(arguments, "account")
        if case .invalidType = accountArg {
            return errorResult("account must be a string account name or UUID.")
        }
        let requested = accountArg.stringValue
        guard let account = accountSet.resolve(requested) else {
            return errorResult("No HackerRank account matches \"\(requested ?? "")\".")
        }

        let cursorResult = requiredIdentity(arguments, "cursor", required: false)
        if case let .error(message) = cursorResult { return errorResult(message) }

        switch name {
        case "list_candidates":
            let testIDResult = requiredIdentity(arguments, "test_id", required: true)
            switch testIDResult {
            case let .error(message):
                return errorResult(message)
            case .missing:
                return missing("test_id")
            case let .value(id):
                return await list(name, account: account, cursor: cursorResult.value, testID: id)
            }
        default:
            return await list(name, account: account, cursor: cursorResult.value)
        }
    }

    private func unexpectedArguments(for name: String, in arguments: [String: Value]?) -> String? {
        guard let arguments, !arguments.isEmpty else { return nil }
        let allowed = Self.allowedArguments[name] ?? []
        let unknown = arguments.keys.filter { !allowed.contains($0) }.sorted()
        guard !unknown.isEmpty else { return nil }
        return unknown.joined(separator: ", ")
    }

    private static let names: Set<String> = [
        "list_accounts", "list_tests", "list_questions", "list_interviews",
        "list_candidates", "list_users", "list_teams",
    ]

    private static let allowedArguments: [String: Set<String>] = [
        "list_accounts": [],
        "list_tests": ["account", "cursor"],
        "list_questions": ["account", "cursor"],
        "list_interviews": ["account", "cursor"],
        "list_candidates": ["account", "cursor", "test_id"],
        "list_users": ["account", "cursor"],
        "list_teams": ["account", "cursor"],
    ]

    private static var descriptors: [[String: Any]] {
        let account: [String: Any] = [
            "type": "string",
            "description": "Account name or UUID; defaults to the configured default.",
        ]
        let cursor: [String: Any] = [
            "type": "string",
            "description": "Opaque next cursor returned by the preceding page.",
        ]
        func descriptor(
            _ name: String,
            _ description: String,
            properties: [String: Any],
            required: [String] = []
        ) -> [String: Any] {
            var schema: [String: Any] = [
                "type": "object",
                "properties": properties,
                "additionalProperties": false,
            ]
            if !required.isEmpty {
                schema["required"] = required
            }
            return [
                "name": name,
                "description": description,
                "annotations": ["readOnlyHint": true],
                "inputSchema": schema,
            ]
        }
        let page = ["account": account, "cursor": cursor]
        return [
            descriptor("list_accounts", "List configured accounts without credentials.", properties: [:]),
            descriptor("list_tests", "List one page of HackerRank tests.", properties: page),
            descriptor("list_questions", "List one page of HackerRank questions.", properties: page),
            descriptor("list_interviews", "List one page of HackerRank interviews.", properties: page),
            descriptor(
                "list_candidates",
                "List one page of candidates for a test.",
                properties: [
                    "account": account,
                    "cursor": cursor,
                    "test_id": ["type": "string", "description": "The test identifier."],
                ],
                required: ["test_id"]
            ),
            descriptor("list_users", "List one page of organization users.", properties: page),
            descriptor("list_teams", "List one page of organization teams.", properties: page),
        ]
    }

    private func list(
        _ name: String,
        account: HackerRankMCPAccount,
        cursor: String?,
        testID: String? = nil
    ) async -> CallTool.Result {
        let client = await clientCache.client(for: account)
        do {
            let payload: [String: Any]
            switch name {
            case "list_tests":
                let page = try await client.testsPage(after: cursor)
                payload = pagePayload(page, key: "tests", account: account) {
                    [
                        "id": $0.id,
                        "unique_id": $0.uniqueID.map { $0 as Any } ?? NSNull(),
                        "name": $0.name,
                        "state": $0.state.map { $0 as Any } ?? NSNull(),
                        "owner": $0.owner.map { $0 as Any } ?? NSNull(),
                        "draft": $0.draft.map { $0 as Any } ?? NSNull(),
                        "locked": $0.locked.map { $0 as Any } ?? NSNull(),
                        "created_at": $0.createdAt.map { $0 as Any } ?? NSNull(),
                        "starts_at": $0.startTime.map { $0 as Any } ?? NSNull(),
                        "ends_at": $0.endTime.map { $0 as Any } ?? NSNull(),
                        "duration_minutes": $0.duration.map { $0 as Any } ?? NSNull(),
                    ]
                }
            case "list_questions":
                let page = try await client.questionsPage(after: cursor)
                payload = pagePayload(page, key: "questions", account: account) {
                    [
                        "id": $0.id,
                        "name": $0.name,
                        "type": $0.type,
                        "status": $0.status.map { $0 as Any } ?? NSNull(),
                        "owner": $0.owner.map { $0 as Any } ?? NSNull(),
                        "tags": $0.tags.map { $0 as Any } ?? NSNull(),
                        "languages": $0.languages.map { $0 as Any } ?? NSNull(),
                        "recommended_duration": $0.recommendedDuration.map { $0 as Any } ?? NSNull(),
                    ]
                }
            case "list_interviews":
                let page = try await client.interviewsPage(after: cursor)
                payload = pagePayload(page, key: "interviews", account: account) {
                    [
                        "id": $0.id,
                        "title": $0.title.map { $0 as Any } ?? NSNull(),
                        "status": $0.status,
                        "url": $0.url.isEmpty ? NSNull() : $0.url,
                        "scheduled_from": $0.scheduledFrom.map { $0 as Any } ?? NSNull(),
                        "scheduled_to": $0.scheduledTo.map { $0 as Any } ?? NSNull(),
                        "created_at": $0.createdAt.map { $0 as Any } ?? NSNull(),
                        "updated_at": $0.updatedAt.map { $0 as Any } ?? NSNull(),
                        "ended_at": $0.endedAt.map { $0 as Any } ?? NSNull(),
                    ]
                }
            case "list_candidates":
                guard let testID else { return missing("test_id") }
                let page = try await client.candidatesPage(testID: testID, after: cursor)
                payload = pagePayload(page, key: "candidates", account: account) {
                    [
                        "id": $0.id,
                        "email": $0.email,
                        "name": $0.fullName.map { $0 as Any } ?? NSNull(),
                        "score": $0.score.map { $0 as Any } ?? NSNull(),
                        "percentage_score": $0.percentageScore.map { $0 as Any } ?? NSNull(),
                        "status": $0.status.map { $0 as Any } ?? NSNull(),
                        "status_label": candidateStatusLabel($0.status).map { $0 as Any } ?? NSNull(),
                        "ats_state": $0.atsState.map { $0 as Any } ?? NSNull(),
                        "integrity_status": $0.integrityStatus.map { $0 as Any } ?? NSNull(),
                        "integrity_summary": $0.integritySummary.map { $0 as Any } ?? NSNull(),
                        "attempt_start_time": $0.attemptStartTime.map { $0 as Any } ?? NSNull(),
                        "attempt_end_time": $0.attemptEndTime.map { $0 as Any } ?? NSNull(),
                        "invited_on": $0.invitedOn.map { $0 as Any } ?? NSNull(),
                        "invite_valid": $0.inviteValid.map { $0 as Any } ?? NSNull(),
                    ]
                }
            case "list_users":
                let page = try await client.usersPage(after: cursor)
                payload = pagePayload(page, key: "users", account: account) {
                    [
                        "id": $0.id,
                        "email": $0.email,
                        "first_name": $0.firstName.map { $0 as Any } ?? NSNull(),
                        "last_name": $0.lastName.map { $0 as Any } ?? NSNull(),
                        "role": $0.role.map { $0 as Any } ?? NSNull(),
                        "status": $0.status.map { $0 as Any } ?? NSNull(),
                        "teams": $0.teams.map { $0 as Any } ?? NSNull(),
                        "activated": $0.activated.map { $0 as Any } ?? NSNull(),
                        "company_admin": $0.companyAdmin.map { $0 as Any } ?? NSNull(),
                        "team_admin": $0.teamAdmin.map { $0 as Any } ?? NSNull(),
                        "questions_permission": $0.questionsPermission.map { $0 as Any } ?? NSNull(),
                        "tests_permission": $0.testsPermission.map { $0 as Any } ?? NSNull(),
                        "interviews_permission": $0.interviewsPermission.map { $0 as Any } ?? NSNull(),
                        "candidates_permission": $0.candidatesPermission.map { $0 as Any } ?? NSNull(),
                    ]
                }
            case "list_teams":
                let page = try await client.teamsPage(after: cursor)
                payload = pagePayload(page, key: "teams", account: account) {
                    [
                        "id": $0.id,
                        "name": $0.name,
                        "owner": $0.owner.map { $0 as Any } ?? NSNull(),
                        "created_at": $0.createdAt.map { $0 as Any } ?? NSNull(),
                        "locations": $0.locations.map { $0 as Any } ?? NSNull(),
                        "departments": $0.departments.map { $0 as Any } ?? NSNull(),
                        "recruiters": $0.recruiterCount.map { $0 as Any } ?? NSNull(),
                        "developers": $0.developerCount.map { $0 as Any } ?? NSNull(),
                        "recruiter_cap": $0.recruiterCap.map { $0 as Any } ?? NSNull(),
                        "developer_cap": $0.developerCap.map { $0 as Any } ?? NSNull(),
                    ]
                }
            default:
                return errorResult("Unknown tool: \(name)")
            }
            return compactJSONResult(payload)
        } catch {
            return errorResult(toolErrorMessage(error))
        }
    }

    private func pagePayload<Item: Sendable>(
        _ page: Page<Item>,
        key: String,
        account: HackerRankMCPAccount,
        transform: (Item) -> [String: Any]
    ) -> [String: Any] {
        let items = page.items.compactMap { item -> [String: Any]? in
            let row = transform(item)
            guard let id = row["id"] as? String,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return row
        }
        let nextCursor = page.next.flatMap { cursor -> String? in
            let trimmed = cursor.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return [
            "account": account.name,
            key: items,
            "returned_count": items.count,
            "total_count": page.totalCount.map { $0 as Any } ?? NSNull(),
            "has_more": nextCursor != nil,
            "next_cursor": nextCursor.map { $0 as Any } ?? NSNull(),
        ]
    }
}

func toolErrorMessage(_ error: Error) -> String {
    if let error = error as? HackerRankError {
        switch error {
        case .missingAPIKey:
            return "Missing HackerRank API token."
        case let .http(status, _):
            return "HackerRank API request failed (HTTP \(status))."
        case .decode:
            return "Could not decode the HackerRank API response."
        case .network:
            return "Could not reach the HackerRank API."
        }
    }
    return "The HackerRank request failed."
}

private enum TypedStringArgument {
    case missing
    case invalidType
    case value(String)

    var stringValue: String? {
        if case let .value(value) = self { return value }
        return nil
    }
}

private func typedStringArgument(_ arguments: [String: Value]?, _ key: String) -> TypedStringArgument {
    guard let arguments, let value = arguments[key] else { return .missing }
    switch value {
    case let .string(string): return .value(string)
    case .null: return .missing
    default: return .invalidType
    }
}

private enum IdentityArgument {
    case missing
    case value(String)
    case error(String)

    var value: String? {
        if case let .value(value) = self { return value }
        return nil
    }
}

enum ParsedToolIdentity: Equatable {
    case missing
    case value(String)
    case invalid(String)
}

func parseToolIdentity(
    _ arguments: [String: Value]?,
    _ key: String
) -> ParsedToolIdentity {
    guard let arguments, let raw = arguments[key] else { return .missing }
    let string: String
    switch raw {
    case let .string(value): string = value
    case let .int(value): string = String(value)
    case let .double(value):
        if value.rounded() == value, value >= Double(Int.min), value <= Double(Int.max) {
            string = String(Int(value))
        } else {
            string = String(value)
        }
    case .null:
        return .missing
    default:
        return .invalid("\(key) must be a string or number identifier.")
    }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return .invalid("\(key) must not be blank.")
    }
    return .value(trimmed)
}

private func requiredIdentity(
    _ arguments: [String: Value]?,
    _ key: String,
    required: Bool
) -> IdentityArgument {
    switch parseToolIdentity(arguments, key) {
    case let .invalid(message): return .error(message)
    case let .value(value): return .value(value)
    case .missing: return .missing
    }
}

private func compactJSONResult(_ value: Any) -> CallTool.Result {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
        return errorResult("Could not encode the result.")
    }
    let text = String(decoding: data, as: UTF8.self)
    return CallTool.Result(
        content: [.text(text: text, annotations: nil, _meta: nil)]
    )
}

private func errorResult(_ message: String) -> CallTool.Result {
    CallTool.Result(
        content: [.text(text: message, annotations: nil, _meta: nil)],
        isError: true
    )
}

private func missing(_ name: String) -> CallTool.Result {
    errorResult("Missing required argument: \(name)")
}
