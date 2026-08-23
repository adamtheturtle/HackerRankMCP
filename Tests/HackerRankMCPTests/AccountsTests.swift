import Foundation
@testable import HackerRankMCP
import Testing

struct AccountsTests {
    @Test func `account set resolves its default and named accounts`() throws {
        let first = HackerRankMCPAccount(name: "Work", token: "one")
        let second = HackerRankMCPAccount(name: "EU", token: "two")
        let set = try HackerRankMCPAccountSet(
            accounts: [first, second],
            defaultAccountID: second.id
        )

        #expect(set.resolve(nil)?.id == second.id)
        #expect(set.resolve("work")?.id == first.id)
        #expect(set.resolve(first.id.uuidString)?.id == first.id)
    }

    @Test func `environment configuration requires a token`() {
        #expect(throws: HackerRankMCPConfigError.noAccounts) {
            try loadHackerRankMCPAccounts(environment: [:])
        }
    }

    @Test func `environment configuration rejects unsafe base URLs`() {
        #expect(throws: HackerRankMCPConfigError.invalidBaseURL("http://example.com")) {
            try loadHackerRankMCPAccounts(environment: [
                "HACKERRANK_API_TOKEN": "secret",
                "HACKERRANK_BASE_URL": "http://example.com",
            ])
        }
    }

    @Test func `missing config file falls back to environment token`() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("hackerrank-mcp-missing-\(UUID().uuidString).json")
        let set = try loadHackerRankMCPAccounts(environment: [
            "HACKERRANK_MCP_CONFIG": missing.path,
            "HACKERRANK_API_TOKEN": "secret",
            "HACKERRANK_ACCOUNT_NAME": "Fallback",
        ])
        #expect(set.accounts.count == 1)
        #expect(set.accounts[0].name == "Fallback")
        #expect(set.accounts[0].token == "secret")
    }

    @Test func `invalid JSON config surfaces domain error`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hackerrank-mcp-\(UUID().uuidString).json")
        try Data("{not-json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try loadHackerRankMCPAccounts(environment: ["HACKERRANK_MCP_CONFIG": url.path])
            Issue.record("Expected invalidConfig")
        } catch let error as HackerRankMCPConfigError {
            guard case .invalidConfig = error else {
                Issue.record("Expected invalidConfig, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected HackerRankMCPConfigError, got \(error)")
        }
    }

    @Test func `missing required config field surfaces domain error`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hackerrank-mcp-\(UUID().uuidString).json")
        try Data(#"{"accounts":[{"token":"secret"}]}"#.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try loadHackerRankMCPAccounts(environment: ["HACKERRANK_MCP_CONFIG": url.path])
            Issue.record("Expected invalidConfig")
        } catch let error as HackerRankMCPConfigError {
            guard case let .invalidConfig(detail) = error else {
                Issue.record("Expected invalidConfig, got \(error)")
                return
            }
            #expect(detail.contains("name"))
        } catch {
            Issue.record("Expected HackerRankMCPConfigError, got \(error)")
        }
    }

    @Test func `valid config file loads accounts and default`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hackerrank-mcp-\(UUID().uuidString).json")
        try Data(
            """
            {"accounts":[
              {"name":"Work","token":"secret","base_url":"https://www.hackerrank.com","default":true},
              {"name":"EU","token":"other"}
            ]}
            """.utf8
        ).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let set = try loadHackerRankMCPAccounts(environment: ["HACKERRANK_MCP_CONFIG": url.path])
        #expect(set.accounts.count == 2)
        #expect(set.resolve(nil)?.name == "Work")
        #expect(set.resolve("eu")?.token == "other")
    }
}
