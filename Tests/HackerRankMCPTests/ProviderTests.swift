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

    @Test func `non-string account arguments are rejected`() async throws {
        let account = HackerRankMCPAccount(name: "Work", token: "secret")
        let provider = try HackerRankProvider(
            accountSet: HackerRankMCPAccountSet(accounts: [account])
        )

        let boolArg = await provider.callTool("list_tests", arguments: ["account": .bool(true)])
        #expect(boolArg.isError == true)
        #expect(text(from: boolArg).contains("must be a string"))

        let numeric = await provider.callTool("list_tests", arguments: ["account": .int(999)])
        #expect(numeric.isError == true)
        #expect(text(from: numeric).contains("must be a string"))
    }

    @Test func `list accounts never exposes tokens`() async throws {
        let account = HackerRankMCPAccount(name: "Work", token: "super-secret")
        let provider = try HackerRankProvider(
            accountSet: HackerRankMCPAccountSet(accounts: [account])
        )

        let result = await provider.callTool("list_accounts", arguments: nil)
        let output = text(from: result)
        #expect(output.contains("Work"))
        #expect(!output.contains("super-secret"))
    }

    @Test func `list accounts ignores account resolution and rejects unexpected args`() async throws {
        let account = HackerRankMCPAccount(name: "Work", token: "secret")
        let provider = try HackerRankProvider(
            accountSet: HackerRankMCPAccountSet(accounts: [account])
        )

        let ok = await provider.callTool("list_accounts", arguments: nil)
        #expect(ok.isError != true)
        #expect(text(from: ok).contains("Work"))

        let bogus = await provider.callTool(
            "list_accounts",
            arguments: ["account": .string("missing")]
        )
        #expect(bogus.isError == true)
        #expect(text(from: bogus).contains("Unexpected argument"))
    }

    @Test func `unknown account error uses ASCII quotes`() async throws {
        let account = HackerRankMCPAccount(name: "Work", token: "secret")
        let provider = try HackerRankProvider(
            accountSet: HackerRankMCPAccountSet(accounts: [account])
        )

        let result = await provider.callTool(
            "list_tests",
            arguments: ["account": .string("nope")]
        )
        let message = text(from: result)
        #expect(result.isError == true)
        #expect(message.contains("\"nope\""))
        #expect(!message.contains("“"))
        #expect(!message.contains("”"))
    }
}

private func text(from result: CallTool.Result) -> String {
    result.content.compactMap { content -> String? in
        if case let .text(text, _, _) = content {
            return text
        }
        return nil
    }.joined()
}

private func text(from result: CallTool.Result) -> String {
    result.content.compactMap { content -> String? in
        if case let .text(text, _, _) = content { return text }
        return nil
    }.joined()
}
