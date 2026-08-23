import HackerRankMCP
import MCP
import Testing

struct ProviderTests {
    @Test func `provider advertises read-only tools`() async throws {
        let account = HackerRankMCPAccount(name: "Work", token: "secret")
        let provider = try HackerRankProvider(
            accountSet: HackerRankMCPAccountSet(accounts: [account])
        )

        let tools = await provider.tools()
        #expect(tools.contains { $0.name == "list_tests" })
        #expect(tools.contains { $0.name == "list_candidates" })
        #expect(!tools.contains { $0.name.hasPrefix("delete_") })
    }

    @Test func `list accounts never exposes tokens`() async throws {
        let account = HackerRankMCPAccount(name: "Work", token: "super-secret")
        let provider = try HackerRankProvider(
            accountSet: HackerRankMCPAccountSet(accounts: [account])
        )

        let result = await provider.callTool("list_accounts", arguments: nil)
        let output = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content {
                return text
            }
            return nil
        }.joined()
        #expect(output.contains("Work"))
        #expect(!output.contains("super-secret"))
        #expect(!output.contains("\n  "))
    }
}
