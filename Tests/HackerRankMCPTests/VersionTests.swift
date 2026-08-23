import HackerRankMCP
import Testing

struct VersionTests {
    @Test func `advertised version matches single source constant`() {
        #expect(hackerRankMCPVersion == HackerRankMCPVersion.semver)
        #expect(hackerRankMCPVersion.split(separator: ".").count == 3)
    }
}
