import Foundation
import HackerRankKit
import MCP
import MCPKit

public struct HackerRankProvider: MCPToolProvider {
    public let accountSet: HackerRankMCPAccountSet

    public init(accountSet: HackerRankMCPAccountSet) {
        self.accountSet = accountSet
    }

    public func tools() async -> [Tool] {
        mcpTools(from: Self.descriptors)
    }

    public func callTool(_ name: String, arguments: [String: Value]?) async -> CallTool.Result {
        guard Self.names.contains(name) else { return errorResult("Unknown tool: \(name)") }
        let requested = stringArgument(arguments, "account")
        guard let account = accountSet.resolve(requested) else {
            return errorResult("No HackerRank account matches “\(requested ?? "")”.")
        }
        let cursor = stringArgument(arguments, "cursor")
        switch name {
        case "list_accounts":
            return jsonResult(["accounts": accountSet.accounts.map {
                ["id": $0.id.uuidString, "name": $0.name, "base_url": $0.baseURL.absoluteString]
            }])
        case "list_candidates":
            guard let id = stringArgument(arguments, "test_id") else { return missing("test_id") }
            return await list(name, account: account, cursor: cursor, testID: id)
        default:
            return await list(name, account: account, cursor: cursor)
        }
    }

    private static let names: Set<String> = [
        "list_accounts", "list_tests", "list_questions", "list_interviews",
        "list_candidates", "list_users", "list_teams",
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

    @MainActor
    private func list(
        _ name: String,
        account: HackerRankMCPAccount,
        cursor: String?,
        testID: String? = nil
    ) async -> CallTool.Result {
        let client = HackerRankClient(token: account.token, baseURL: account.baseURL)
        do {
            let payload: [String: Any]
            switch name {
            case "list_tests":
                let page = try await client.testsPage(after: cursor)
                payload = pagePayload(page, key: "tests", account: account) {
                    [
                        "id": $0.id,
                        "name": $0.name,
                        "state": $0.state ?? "",
                        // The assessment window only started decoding in HackerRankKit
                        // 0.8.0: the wire keys are `starttime`/`endtime`, and the client
                        // had been reading `start_time`/`end_time`, so these were always
                        // absent before.
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
                    ["id": $0.id, "title": $0.title ?? "", "status": $0.status]
                }
            case "list_candidates":
                guard let testID else { return missing("test_id") }
                let page = try await client.candidatesPage(testID: testID, after: cursor)
                payload = pagePayload(page, key: "candidates", account: account) {
                    [
                        "id": $0.id,
                        "email": $0.email,
                        "name": $0.fullName ?? "",
                        "score": $0.score.map { $0 as Any } ?? NSNull(),
                        "percentage_score": $0.percentageScore.map { $0 as Any } ?? NSNull(),
                        "status": $0.status.map { $0 as Any } ?? NSNull(),
                        "ats_state": $0.atsState.map { $0 as Any } ?? NSNull(),
                        // Whether an invite is still usable is a question an agent asks
                        // constantly, and the client only began decoding it in 0.8.0.
                        "invite_valid": $0.inviteValid.map { $0 as Any } ?? NSNull(),
                    ]
                }
            case "list_users":
                let page = try await client.usersPage(after: cursor)
                payload = pagePayload(page, key: "users", account: account) {
                    [
                        "id": $0.id,
                        "email": $0.email,
                        "first_name": $0.firstName ?? "",
                        "last_name": $0.lastName ?? "",
                        "role": $0.role ?? "",
                    ]
                }
            case "list_teams":
                let page = try await client.teamsPage(after: cursor)
                payload = pagePayload(page, key: "teams", account: account) {
                    [
                        "id": $0.id,
                        "name": $0.name,
                        "recruiters": $0.recruiterCount.map { $0 as Any } ?? NSNull(),
                        "developers": $0.developerCount.map { $0 as Any } ?? NSNull(),
                        // `interviewers` is gone: HackerRank has no such field, so it was
                        // reported as null for every real team. The seat caps are the
                        // documented counterparts and do arrive.
                        "recruiter_cap": $0.recruiterCap.map { $0 as Any } ?? NSNull(),
                        "developer_cap": $0.developerCap.map { $0 as Any } ?? NSNull(),
                    ]
                }
            default:
                return errorResult("Unknown tool: \(name)")
            }
            return jsonResult(payload)
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    @MainActor
    private func pagePayload<Item: Sendable>(
        _ page: Page<Item>,
        key: String,
        account: HackerRankMCPAccount,
        transform: (Item) -> [String: Any]
    ) -> [String: Any] {
        [
            "account": account.name,
            key: page.items.map(transform),
            "returned_count": page.items.count,
            "total_count": page.totalCount.map { $0 as Any } ?? NSNull(),
            "has_more": page.next != nil,
            "next_cursor": page.next ?? NSNull(),
        ]
    }
}

private func jsonResult(_ value: Any) -> CallTool.Result {
    guard let data = try? JSONSerialization.data(
        withJSONObject: value,
        options: [.prettyPrinted, .sortedKeys]
    ) else {
        return errorResult("Could not encode the result.")
    }
    return CallTool.Result(
        content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)]
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
