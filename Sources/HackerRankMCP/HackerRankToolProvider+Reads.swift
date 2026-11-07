import Foundation
import HackerRankKit
import MCP

extension HackerRankToolProvider {
    static var additionalReadDescriptors: [[String: Any]] {
        let names = Set(descriptors.compactMap { $0["name"] as? String })
        return HackerRankProvider.readDescriptors.filter { !names.contains($0["name"] as? String ?? "") }
    }

    @MainActor
    func callRead(_ operation: ReadOperation, arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let accounts = try HackerRankMCPAccountSet(accounts: [resolved])
            let cache = HackerRankClientCache { try await self.client(for: $0) }
            let reader = HackerRankProvider(accountSet: accounts, clientCache: cache)
            return await reader.read(operation, arguments: arguments, account: resolved)
        } catch {
            return errorResult(toolErrorMessage(error))
        }
    }
}
