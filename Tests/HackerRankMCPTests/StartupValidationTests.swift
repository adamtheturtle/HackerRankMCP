import HackerRankKit
import HackerRankKitMock
@testable import HackerRankMCP
import Testing

struct StartupValidationTests {
    @Test func `startup validation succeeds against mock server`() async throws {
        let account = HackerRankMCPAccount(name: "Work", token: "demo")
        let set = try HackerRankMCPAccountSet(accounts: [account])
        try await validateHackerRankAccountsOnStartup(set) { account in
            let client = HackerRankClient.mock(key: "startup-\(account.name)-\(UUID().uuidString)")
            _ = try await client.usersPage(after: nil)
        }
    }

    @Test func `forbidden probe maps to startup validation failure not invalid token`() async throws {
        let account = HackerRankMCPAccount(name: "Work", token: "secret")
        let set = try HackerRankMCPAccountSet(accounts: [account])
        do {
            try await validateHackerRankAccountsOnStartup(set) { _ in
                throw HackerRankError.http(403, "forbidden")
            }
            Issue.record("expected startup validation to throw")
        } catch let error as HackerRankMCPConfigError {
            guard case let .startupValidationFailed(name, _) = error else {
                Issue.record("expected startupValidationFailed, got \(error)")
                return
            }
            #expect(name == "Work")
            #expect(error != .invalidToken("Work"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
