import Foundation
import HackerRankMCP
import Testing

struct VersionTests {
    @Test func `version string is non-empty semver-shaped`() {
        #expect(hackerRankMCPVersion == HackerRankMCPVersion.semver)
        #expect(hackerRankMCPVersion.split(separator: ".").count == 3)
    }

    @Test func `release workflow greps the semver source of truth`() throws {
        let workflow = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".github/workflows/release.yml")
        let text = try String(contentsOf: workflow, encoding: .utf8)
        #expect(text.contains(#"grep -Fq "public static let semver = \"$version\"" Sources/HackerRankMCP/ReleaseVersion.swift"#))
        #expect(!text.contains(#"grep -Fq "public let hackerRankMCPVersion = \"$version\"" Sources/HackerRankMCP/ReleaseVersion.swift"#))
    }
}
