import Foundation
import HackerRankKit

/// Validates configured accounts can reach the HackerRank API before serving MCP tools.
public func validateHackerRankAccountsOnStartup(_ accountSet: HackerRankMCPAccountSet) async throws {
    guard let account = accountSet.resolve(nil) else {
        throw HackerRankMCPConfigError.noAccounts
    }
    let client = HackerRankClient(token: account.token, baseURL: account.baseURL)
    do {
        _ = try await client.usersPage(after: nil)
    } catch let error as HackerRankError {
        switch error {
        case .missingAPIKey:
            throw HackerRankMCPConfigError.noAccounts
        case let .http(401, _), let .http(403, _):
            throw HackerRankMCPConfigError.invalidToken(account.name)
        default:
            throw HackerRankMCPConfigError.startupValidationFailed(account.name, String(describing: error))
        }
    } catch {
        throw HackerRankMCPConfigError.startupValidationFailed(account.name, error.localizedDescription)
    }
}
