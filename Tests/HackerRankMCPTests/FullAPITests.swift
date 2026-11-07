import Foundation
import HackerRankKit
import HackerRankKitMock
@testable import HackerRankMCP
import MCP
import Testing

struct FullAPITests {
    @Test func `all 76 documented operations are advertised and runnable with writes enabled`() async throws {
        let client = await MainActor.run { HackerRankClient.mock(key: "full-api-\(UUID().uuidString)") }
        let account = HackerRankMCPAccount(name: "Demo", token: "v3-synthetic", scimToken: "scim-synthetic")
        let provider = try HackerRankProvider(
            accountSet: HackerRankMCPAccountSet(accounts: [account]),
            clientCache: HackerRankClientCache { _ in client }, allowWrites: true
        )
        let catalogue = try HackerRankClient.apiCatalogue()
        let tools = await provider.tools()
        #expect(Set(tools.filter { $0.name.hasPrefix("api_") }.map(\.name)) == Set(catalogue.operations.map(\.id)))
        for operation in catalogue.operations {
            var path: [String: Value] = [:]
            var query: [String: Value] = [:]
            for parameter in operation.parameters {
                if parameter.location == "path" {
                    path[parameter.name] = .string("1")
                }
                if parameter.location == "query", parameter.required {
                    query[parameter.name] = .string("1")
                }
            }
            var arguments: [String: Value] = ["path": .object(path), "query": .object(query)]
            if operation.bodyRequired {
                arguments["body"] = .object([:])
            }
            let result = await provider.callTool(operation.id, arguments: arguments)
            #expect(result.isError != true, "\(operation.id) must have a runnable handler")
            let text = result.content.compactMap { content -> String? in
                if case let .text(text, _, _) = content {
                    return text
                }
                return nil
            }.joined()
            #expect(!text.contains(account.token))
            #expect(!text.contains(account.scimToken ?? "not-a-real-token"))
        }
    }

    @Test func `disabled writes cannot be invoked by name`() async throws {
        let account = HackerRankMCPAccount(name: "Demo", token: "synthetic")
        let provider = try HackerRankProvider(accountSet: HackerRankMCPAccountSet(accounts: [account]))
        let tools = await provider.tools()
        #expect(!tools.contains { $0.name == "api_create_user" })
        let result = await provider.callTool("api_create_user", arguments: ["body": .object([:])])
        #expect(result.isError == true)
        #expect(tools.allSatisfy { $0.annotations.readOnlyHint == true })
    }

    @Test func `write configuration and separate provisioning credentials load explicitly`() throws {
        #expect(try hackerRankMCPWritesEnabled(environment: [:]) == false)
        #expect(try hackerRankMCPWritesEnabled(environment: ["HACKERRANK_MCP_ALLOW_WRITES": "true"]))
        #expect(throws: HackerRankMCPConfigError.self) {
            try hackerRankMCPWritesEnabled(environment: ["HACKERRANK_MCP_ALLOW_WRITES": "yes"])
        }
        let accounts = try loadHackerRankMCPAccounts(environment: [
            "HACKERRANK_API_TOKEN": "v3-synthetic", "HACKERRANK_SCIM_API_TOKEN": "scim-synthetic",
        ])
        #expect(accounts.accounts.first?.scimToken == "scim-synthetic")
    }
}
