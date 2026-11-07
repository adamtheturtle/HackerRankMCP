import Foundation
import HackerRankKit
import MCP

@MainActor
extension HackerRankToolProvider {
    nonisolated static var writeDescriptors: [[String: Any]] {
        legacyWriteDescriptors + fullAPIDescriptors(allowWrites: true).filter {
            ($0["annotations"] as? [String: Bool])?["readOnlyHint"] == false
        }
    }

    func callFullAPI(_ name: String, arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        do {
            guard let operation = try HackerRankClient.apiCatalogue().operations.first(where: { $0.id == name }) else {
                return errorResult("Unknown tool: \(name)")
            }
            guard allowWrites || !operation.isWrite else { return errorResult(writeDisabledMessage) }
            guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

            let input = try fullAPIInputs(arguments)
            let client = try await client(for: resolved)
            let result = try await client.executeAPI(
                name, pathParameters: input.pathParameters, query: input.query, body: input.body,
                scimToken: resolved.scimToken
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return CallTool.Result(content: [.text(
                text: String(data: data, encoding: .utf8) ?? "{}",
                annotations: nil,
                _meta: nil
            )])
        } catch let HackerRankError.http(0, message) {
            return errorResult(message)
        } catch {
            return errorResult(toolErrorMessage(error))
        }
    }
}
