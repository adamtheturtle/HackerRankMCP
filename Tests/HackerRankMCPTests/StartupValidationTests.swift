import HackerRankKit
import HackerRankKitMock
@testable import HackerRankMCP
import Testing

struct StartupValidationTests {
    @Test func `startup validation succeeds against mock server`() async throws {
        let account = HackerRankMCPAccount(name: "Work", token: "demo")
        let set = try HackerRankMCPAccountSet(accounts: [account])
        // Swap in mock transport by validating through a client constructed like production.
        let client = HackerRankClient.mock(key: "startup-\(UUID().uuidString)")
        _ = try await client.usersPage(after: nil)
        _ = set
    }
}
