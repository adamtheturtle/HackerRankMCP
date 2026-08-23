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

    @Test func `validated base URL rejects trailing slash path and loopback`() {
        #expect(throws: HackerRankMCPConfigError.invalidBaseURL("https://www.hackerrank.com/")) {
            try loadHackerRankMCPAccounts(environment: [
                "HACKERRANK_API_TOKEN": "secret",
                "HACKERRANK_BASE_URL": "https://www.hackerrank.com/",
            ])
        }
        #expect(throws: HackerRankMCPConfigError.invalidBaseURL("https://www.hackerrank.com/xavier")) {
            try loadHackerRankMCPAccounts(environment: [
                "HACKERRANK_API_TOKEN": "secret",
                "HACKERRANK_BASE_URL": "https://www.hackerrank.com/xavier",
            ])
        }
        #expect(throws: HackerRankMCPConfigError.invalidBaseURL("https://127.0.0.1")) {
            try loadHackerRankMCPAccounts(environment: [
                "HACKERRANK_API_TOKEN": "secret",
                "HACKERRANK_BASE_URL": "https://127.0.0.1",
            ])
        }
    }

    @Test func `blank account names are rejected`() {
        #expect(throws: HackerRankMCPConfigError.blankAccountName) {
            try HackerRankMCPAccountSet(accounts: [
                HackerRankMCPAccount(name: "   ", token: "secret"),
            ])
        }
    }

    @Test func `empty env token is distinct from missing token`() {
        #expect(throws: HackerRankMCPConfigError.emptyToken("HackerRank")) {
            try loadHackerRankMCPAccounts(environment: ["HACKERRANK_API_TOKEN": ""])
        }
    }

    @Test func `config file rejects empty tokens and multiple defaults`() throws {
        let emptyToken = try writeTempConfig("""
        {"accounts":[{"name":"Work","token":""}]}
        """)
        defer { try? FileManager.default.removeItem(at: emptyToken) }
        #expect(throws: HackerRankMCPConfigError.emptyToken("Work")) {
            try loadHackerRankMCPAccounts(environment: [
                "HACKERRANK_MCP_CONFIG": emptyToken.path,
            ])
        }

        let multiDefault = try writeTempConfig("""
        {"accounts":[
          {"name":"A","token":"one","default":true},
          {"name":"B","token":"two","default":true}
        ]}
        """)
        defer { try? FileManager.default.removeItem(at: multiDefault) }
        #expect(throws: HackerRankMCPConfigError.multipleDefaults) {
            try loadHackerRankMCPAccounts(environment: [
                "HACKERRANK_MCP_CONFIG": multiDefault.path,
            ])
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

    @Test func `relative config paths are rejected`() {
        #expect(throws: HackerRankMCPConfigError.relativeConfigPath("accounts.json")) {
            try loadHackerRankMCPAccounts(environment: [
                "HACKERRANK_MCP_CONFIG": "accounts.json",
            ])
        }
    }
}

    @Test func `missing config file falls back to env token`() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("hackerrank-mcp-missing-\(UUID().uuidString).json")
        let set = try loadHackerRankMCPAccounts(environment: [
            "HACKERRANK_MCP_CONFIG": missing.path,
            "HACKERRANK_API_TOKEN": "from-env",
        ])
        #expect(set.resolve(nil)?.token == "from-env")
    }

    @Test func `unreadable config file does not fall back to env token`() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hackerrank-mcp-unreadable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = dir.appendingPathComponent("accounts.json")
        try Data(#"{"accounts":[{"name":"Work","token":"file-token"}]}"#.utf8).write(to: config)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)

        #expect(throws: HackerRankMCPConfigError.self) {
            try loadHackerRankMCPAccounts(environment: [
                "HACKERRANK_MCP_CONFIG": config.path,
                "HACKERRANK_API_TOKEN": "from-env",
            ])
        }
    }

private func writeTempConfig(_ contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("hackerrank-mcp-\(UUID().uuidString).json")
    try Data(contents.utf8).write(to: url)
    return url
}
