@testable import HackerRankMCP
import MCP
import Testing

struct WhitespaceIdentityTests {
    @Test func `blank cursor and test_id are rejected locally`() async throws {
        let account = HackerRankMCPAccount(name: "Work", token: "secret")
        let provider = try HackerRankProvider(
            accountSet: HackerRankMCPAccountSet(accounts: [account])
        )

        let cursor = await provider.callTool("list_tests", arguments: ["cursor": .string("   ")])
        #expect(cursor.isError == true)
        #expect(text(from: cursor).contains("cursor must not be blank"))

        let blankID = await provider.callTool(
            "list_candidates",
            arguments: ["test_id": .string("\t")]
        )
        #expect(blankID.isError == true)
        #expect(text(from: blankID).contains("test_id must not be blank"))
    }

    @Test func `whole-number double test_id coerces without fractional suffix`() {
        #expect(parseToolIdentity(["test_id": .double(42.0)], "test_id") == .value("42"))
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
