import Foundation
import HackerRankKit
import HackerRankKitMock
import HackerRankMCP
import MCP
import Testing

@MainActor
struct HostIntegrationTests {
    @Test func `account selection and rotated credentials are resolved for every call`() async throws {
        let one = HackerRankMCPAccount(name: "One", token: "first-token")
        let two = HackerRankMCPAccount(name: "Two", token: "second-token")
        let host = Host(accounts: [one, two], selected: one.id)
        let provider = host.provider()
        _ = await provider.callTool("list_tests", arguments: nil)
        host.selected = two.id
        _ = await provider.callTool("list_tests", arguments: nil)
        host.accounts[1].token = "rotated-token"
        host.accounts[1].scimToken = "provisioning-token"
        host.accounts[1].baseURL = try #require(URL(string: "https://regional.example.com"))
        _ = await provider.callTool("api_list_all_tests", arguments: nil)
        #expect(host.requests.map(\.id) == [one.id, two.id, two.id])
        #expect(host.requests.last?.token == "rotated-token")
        #expect(host.requests.last?.scimToken == "provisioning-token")
        #expect(host.requests.last?.baseURL.host == "regional.example.com")
    }

    @Test func `empty merged and ambiguous accounts fail before creating a client`() async {
        let host = Host(accounts: [], selected: nil)
        let provider = host.provider()
        #expect(await provider.callTool("list_tests", arguments: nil).isError == true)
        let one = HackerRankMCPAccount(name: "Same", token: "first-token")
        let two = HackerRankMCPAccount(name: "Same", token: "second-token")
        host.accounts = [one, two]
        host.merged = true
        host.selected = one.id
        #expect(await provider.callTool("list_tests", arguments: nil).isError == true)
        let ambiguous = await provider.callTool("list_tests", arguments: ["account": .string("Same")])
        #expect(ambiguous.isError == true)
        #expect(text(ambiguous).contains("ambiguous"))
        #expect(host.requests.isEmpty)
        let explicit = await provider.callTool("list_tests", arguments: ["account": .string(two.id.uuidString)])
        #expect(explicit.isError != true)
        #expect(host.requests.map(\.id) == [two.id])
        host.accounts = []
        #expect(await provider.callTool("list_tests", arguments: ["account": .string(two.id.uuidString)]).isError == true)
        #expect(host.requests.count == 1)
    }

    @Test func `standalone global search and embedded test search keep their contracts`() async throws {
        let account = HackerRankMCPAccount(name: "Demo", token: "synthetic")
        let host = Host(accounts: [account], selected: account.id)
        let embedded = host.provider()
        let standalone = try HackerRankProvider(accountSet: HackerRankMCPAccountSet(accounts: [account]))
        let global = try #require(await standalone.tools().first { $0.name == "search_candidates" })
        let perTest = try #require(await embedded.tools().first { $0.name == "search_candidates" })
        let encoder = JSONEncoder()
        let globalSchema = try String(decoding: encoder.encode(global.inputSchema), as: UTF8.self)
        let testSchema = try String(decoding: encoder.encode(perTest.inputSchema), as: UTF8.self)
        #expect(!globalSchema.contains("test_id"))
        #expect(testSchema.contains("test_id"))
        let missing = await embedded.callTool("search_candidates", arguments: ["query": .string("ada")])
        #expect(missing.isError == true)
        #expect(host.requests.isEmpty)
        let result = await embedded.callTool("search_candidates", arguments: ["test_id": .string("t1"), "query": .string("ada")])
        #expect(result.isError != true)
        #expect(text(result).contains("Ada Lovelace"))
    }

    @Test func `write opt-in covers both canonical and friendly tools before client creation`() async {
        let account = HackerRankMCPAccount(name: "Demo", token: "synthetic")
        let host = Host(accounts: [account], selected: account.id)
        let provider = host.provider()
        for tool in ["create_user", "api_create_user", "api_scim_create_user"] {
            let result = await provider.callTool(tool, arguments: ["body": .object([:])])
            #expect(result.isError == true)
        }
        #expect(host.requests.isEmpty)
        #expect(await provider.tools().allSatisfy { $0.annotations.readOnlyHint == true })
    }

    @Test func `host failures cannot leak response bodies or credentials`() async {
        let account = HackerRankMCPAccount(name: "Demo", token: "private-token")
        let provider = HackerRankToolProvider(context: {
            HackerRankMCPContext(accounts: [account], currentAccountID: account.id)
        }, makeClient: { _ in throw HackerRankError.http(403, "private-token response-secret") })
        for tool in ["list_tests", "api_list_all_tests", "get_test"] {
            let result = await provider.callTool(tool, arguments: tool == "get_test" ? ["test_id": .string("t1")] : nil)
            #expect(result.isError == true)
            #expect(!text(result).contains("private-token"))
            #expect(!text(result).contains("response-secret"))
        }
    }
}

@MainActor
private final class Host {
    var accounts: [HackerRankMCPAccount]
    var selected: UUID?
    var merged = false
    var requests: [HackerRankMCPAccount] = []

    init(accounts: [HackerRankMCPAccount], selected: UUID?) {
        self.accounts = accounts
        self.selected = selected
    }

    func provider() -> HackerRankToolProvider {
        HackerRankToolProvider(context: {
            HackerRankMCPContext(accounts: self.accounts, currentAccountID: self.selected, isMergedView: self.merged)
        }, makeClient: { account in
            await MainActor.run {
                self.requests.append(account)
                return HackerRankClient.mock(key: account.id.uuidString)
            }
        })
    }
}

private func text(_ result: CallTool.Result) -> String {
    result.content.compactMap {
        if case let .text(value, _, _) = $0 {
            value
        } else {
            nil
        }
    }.joined()
}
