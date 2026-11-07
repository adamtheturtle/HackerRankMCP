import Foundation
import HackerRankKit
import MCP

struct ReadOperation: Sendable {
    let name: String
    let path: String
    var ids: [String] = []
    var strings: [String] = []
    var integers: [String] = []
    var booleans: [String] = []
    var arrays: [String] = []
    var required: [String] = []
    var paged = false

    var allowedArguments: Set<String> {
        Set(ids + strings + integers + booleans + arrays + ["account"] + (paged ? ["cursor"] : []))
    }

    var descriptor: [String: Any] {
        var properties: [String: Any] = ["account": ["type": "string"]]
        for key in ids + strings {
            properties[key] = ["type": "string"]
        }
        for key in integers {
            properties[key] = ["type": "integer"]
        }
        for key in booleans {
            properties[key] = ["type": "boolean"]
        }
        for key in arrays {
            properties[key] = ["type": "array", "items": ["type": "integer"]]
        }
        if paged {
            properties["cursor"] = ["type": "string", "description": "Previous response's continuation URL or audit next_cursor."]
        }
        return [
            "name": name, "description": "Read HackerRank \(path). Returns the complete API response, including pagination metadata.",
            "annotations": ["readOnlyHint": true],
            "inputSchema": ["type": "object", "properties": properties, "required": ids + required, "additionalProperties": false],
        ]
    }
}

extension HackerRankProvider {
    static let readOperations: [ReadOperation] = [
        .init(name: "get_test", path: "tests/{test_id}", ids: ["test_id"], strings: ["additional_fields", "fields", "expand"]),
        .init(name: "get_question", path: "questions/{question_id}", ids: ["question_id"], strings: ["fields", "expand"]),
        .init(name: "get_interview", path: "interviews/{interview_id}", ids: ["interview_id"], strings: ["fields", "expand"]),
        .init(name: "get_user", path: "users/{user_id}", ids: ["user_id"], strings: ["fields", "expand"]),
        .init(name: "get_current_user", path: "users/me"),
        .init(name: "get_team", path: "teams/{team_id}", ids: ["team_id"], strings: ["fields", "expand"]),
        .init(name: "get_candidate", path: "tests/{test_id}/candidates/{candidate_id}", ids: ["test_id", "candidate_id"], strings: ["additional_fields", "fields", "expand"]),
        .init(name: "candidate_report_pdf", path: "tests/{test_id}/candidates/{candidate_id}/pdf", ids: ["test_id", "candidate_id"]),
        .init(name: "get_interview_transcript", path: "interviews/{interview_id}/transcript", ids: ["interview_id"]),
        .init(name: "get_interview_artifacts", path: "interviews/{interview_id}/artifacts", ids: ["interview_id"]),
        .init(name: "get_interview_notes", path: "interviews/{interview_id}/notes", ids: ["interview_id"], arrays: ["note_ids"]),
        .init(name: "search_users", path: "users/search", strings: ["query"], required: ["query"], paged: true),
        .init(name: "search_candidates", path: "candidates/search", strings: ["query"], required: ["query"], paged: true),
        .init(name: "search_test_candidates", path: "tests/{test_id}/candidates/search", ids: ["test_id"], strings: ["query"], required: ["query"], paged: true),
        .init(name: "list_team_members", path: "teams/{team_id}/users", ids: ["team_id"], paged: true),
        .init(name: "get_team_membership", path: "teams/{team_id}/users/{user_id}", ids: ["team_id", "user_id"]),
        .init(name: "list_test_inviters", path: "tests/{test_id}/inviters", ids: ["test_id"], paged: true),
        .init(name: "list_invite_templates", path: "templates", strings: ["access"], paged: true),
        .init(name: "get_invite_template", path: "templates/{template_id}", ids: ["template_id"]),
        .init(name: "list_interview_templates", path: "interview_templates", strings: ["filter"], paged: true),
        .init(name: "get_interview_template", path: "interview_templates/{template_id}", ids: ["template_id"]),
        .init(name: "list_audit_logs", path: "audit_log/cursor", strings: ["user", "source_type", "source_id", "created_at", "sort", "expand"], booleans: ["include_total"], paged: true),
        .init(name: "list_audit_logs_offset", path: "audit_log", strings: ["user", "source_type", "source_id", "created_at", "sort", "expand"], integers: ["limit", "offset"], paged: true),
    ]

    static var readDescriptors: [[String: Any]] {
        readOperations.map(\.descriptor)
    }

    func read(_ operation: ReadOperation, arguments: [String: Value]?, account: HackerRankMCPAccount) async -> CallTool.Result {
        do {
            let client = try await clientCache.client(for: account)
            let request = try operation.request(arguments: arguments)
            if operation.name == "get_interview_artifacts" {
                let id = try operation.identity("interview_id", arguments: arguments)
                switch try await client.interviewArtifacts(id: id) {
                case let .available(artifacts): return try encodedResult(artifacts)
                case let .pending(pending): return try encodedResult(pending)
                }
            }
            let value = try await client.resourceJSON(path: request.path, after: request.cursor, query: request.query)
            return try encodedResult(value)
        } catch let error as ReadArgumentError {
            return errorResult(error.message)
        } catch {
            return errorResult(toolErrorMessage(error))
        }
    }
}

struct ReadArgumentError: Error { let message: String }

extension ReadOperation {
    func identity(_ key: String, arguments: [String: Value]?) throws -> String {
        switch parseToolIdentity(arguments, key) {
        case let .value(value): return value
        case let .invalid(message): throw ReadArgumentError(message: message)
        case .missing: throw ReadArgumentError(message: "Missing required argument: \(key)")
        }
    }

    func request(arguments: [String: Value]?) throws -> (path: String, cursor: String?, query: [URLQueryItem]) {
        var resolved = path
        for key in ids {
            let raw = try identity(key, arguments: arguments)
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            guard let encoded = raw.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw ReadArgumentError(message: "Could not encode \(key)")
            }
            resolved = resolved.replacingOccurrences(of: "{\(key)}", with: encoded)
        }
        var cursor: String?
        if let value = arguments?["cursor"], value != .null {
            guard case let .string(text) = value, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ReadArgumentError(message: "cursor must be a nonblank string")
            }
            cursor = text
        }
        if path == "audit_log/cursor", let cursor {
            return ("/x/api/v3/\(resolved)", nil, [URLQueryItem(name: "cursor", value: cursor)])
        }
        var query: [URLQueryItem] = []
        for key in strings {
            guard let value = arguments?[key], value != .null else {
                if required.contains(key), cursor == nil {
                    throw ReadArgumentError(message: "Missing required argument: \(key)")
                }
                continue
            }
            guard case let .string(text) = value else { throw ReadArgumentError(message: "\(key) must be a string") }
            if required.contains(key) && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ReadArgumentError(message: "\(key) must not be blank")
            }
            let wireKey = key == "query" && (path == "users/search" || path.hasSuffix("/candidates/search")) ? "search" : key
            query.append(URLQueryItem(name: wireKey, value: text))
        }
        for key in integers + booleans + arrays {
            guard let value = arguments?[key], value != .null else { continue }
            let text: String
            switch value {
            case let .int(number) where integers.contains(key): text = String(number)
            case let .bool(flag) where booleans.contains(key): text = String(flag)
            case let .array(values) where arrays.contains(key):
                text = try values.map { value in
                    guard case let .int(number) = value else { throw ReadArgumentError(message: "\(key) must contain integers") }
                    return String(number)
                }.joined(separator: ",")
            default: throw ReadArgumentError(message: "Invalid type for \(key)")
            }
            query.append(URLQueryItem(name: key, value: text))
        }
        if path.hasSuffix("/pdf"), !query.contains(where: { $0.name == "format" }) {
            query.append(URLQueryItem(name: "format", value: "url"))
        }
        if paged, path != "audit_log/cursor", !query.contains(where: { $0.name == "limit" }) {
            query.append(URLQueryItem(name: "limit", value: "100"))
        }
        return ("/x/api/v3/\(resolved)", cursor, query)
    }
}

private func encodedResult(_ value: some Encodable) throws -> CallTool.Result {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    return CallTool.Result(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)])
}
