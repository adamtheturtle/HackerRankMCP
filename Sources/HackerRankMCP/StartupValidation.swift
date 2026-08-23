import Foundation
import HackerRankKit

/// Validates configured accounts can reach the HackerRank API before serving MCP tools.
public func validateHackerRankAccountsOnStartup(_ accountSet: HackerRankMCPAccountSet) async throws {
    try await validateHackerRankAccountsOnStartup(accountSet) { account in
        let client = await HackerRankClient(token: account.token, baseURL: account.baseURL)
        _ = try await client.usersPage(after: nil)
    }
}

/// Testable entry point that runs an injected probe against the default account.
func validateHackerRankAccountsOnStartup(
    _ accountSet: HackerRankMCPAccountSet,
    probe: @Sendable (HackerRankMCPAccount) async throws -> Void
) async throws {
    guard let account = accountSet.resolve(nil) else {
        throw HackerRankMCPConfigError.noAccounts
    }
    do {
        try await probe(account)
    } catch let error as HackerRankError {
        switch error {
        case .missingAPIKey:
            throw HackerRankMCPConfigError.invalidToken(account.name)
        case .http(401, _):
            throw HackerRankMCPConfigError.invalidToken(account.name)
        default:
            throw HackerRankMCPConfigError.startupValidationFailed(account.name, String(describing: error))
        }
    } catch {
        throw HackerRankMCPConfigError.startupValidationFailed(account.name, error.localizedDescription)
    }
}
