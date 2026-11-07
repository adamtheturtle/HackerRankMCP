import Foundation
import HackerRankKit
import HackerRankKitMock
@testable import HackerRankMCP
import MCP
import Testing

struct ReadOperationsTests {
    @Test func `every advertised read operation runs against the mock`() async throws {
        let client = await MainActor.run { HackerRankClient.mock(key: "read-coverage-\(UUID().uuidString)") }
        let account = HackerRankMCPAccount(name: "Demo", token: "synthetic-token")
        let provider = try HackerRankProvider(
            accountSet: HackerRankMCPAccountSet(accounts: [account]),
            clientCache: HackerRankClientCache { _ in client }
        )
        let tools = await provider.tools()
        #expect(Set(tools.map(\.name)).count == tools.count)
        for operation in HackerRankProvider.readOperations {
            var arguments: [String: Value] = [:]
            for key in operation.ids {
                arguments[key] = .string(key == "interview_id" ? "iv1" : "1")
            }
            for key in operation.required {
                arguments[key] = .string("demo")
            }
            let result = await provider.callTool(operation.name, arguments: arguments)
            #expect(result.isError != true, "\(operation.name) should run through its advertised handler")
            let output = result.content.compactMap { content -> String? in
                if case let .text(text, _, _) = content {
                    return text
                }
                return nil
            }.joined()
            #expect(!output.contains(account.token))
        }
    }

    @Test func `search and audit queries follow their respective contracts`() throws {
        let operations = HackerRankProvider.readOperations
        let global = try #require(operations.first { $0.name == "search_candidates" })
        #expect(try global.request(arguments: ["query": .string("demo")]).query.contains(URLQueryItem(name: "query", value: "demo")))
        let scoped = try #require(operations.first { $0.name == "search_test_candidates" })
        #expect(try scoped.request(arguments: ["query": .string("demo"), "test_id": .string("1")]).query.contains(URLQueryItem(name: "search", value: "demo")))
        let audit = try #require(operations.first { $0.name == "list_audit_logs" })
        let continuation = try audit.request(arguments: ["cursor": .string("opaque+/="), "include_total": .bool(true)])
        #expect(continuation.cursor == nil)
        #expect(continuation.query == [URLQueryItem(name: "cursor", value: "opaque+/=")])
    }

    @Test func `required identities and query types are checked before networking`() async throws {
        let account = HackerRankMCPAccount(name: "Demo", token: "synthetic-token")
        let provider = try HackerRankProvider(accountSet: HackerRankMCPAccountSet(accounts: [account]))
        for (name, arguments) in [
            ("get_test", ["test_id": Value.string(" ")]),
            ("get_interview_notes", ["interview_id": .string("1"), "note_ids": .array([.string("bad")])]),
            ("search_candidates", ["query": .bool(true)]),
            ("list_audit_logs", ["include_total": .string("yes")]),
            ("get_team", ["team_id": .string("1"), "unexpected": .bool(true)]),
        ] {
            let result = await provider.callTool(name, arguments: arguments)
            #expect(result.isError == true)
        }
    }
}
