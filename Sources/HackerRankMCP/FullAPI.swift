import Foundation
import HackerRankKit
import MCP

func fullAPIDescriptors(allowWrites: Bool) -> [[String: Any]] {
    guard let catalogue = try? HackerRankClient.apiCatalogue() else { return [] }
    return catalogue.operations.filter { allowWrites || !$0.isWrite }.compactMap { operation in
        guard case var .object(schema) = catalogue.inputSchema(for: operation),
              case var .object(properties)? = schema["properties"] else { return nil }
        properties["account"] = .object(["type": .string("string")])
        schema["properties"] = .object(properties)
        guard let data = try? JSONEncoder().encode(HackerRankJSONValue.object(schema)),
              let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return [
            "name": operation.id, "description": "\(operation.summary) (\(operation.method) \(operation.path)).",
            "annotations": ["readOnlyHint": !operation.isWrite], "inputSchema": input,
        ]
    }
}

func fullAPIInputs(_ arguments: [String: Value]?) throws -> HackerRankAPIInputs {
    let values = arguments ?? [:]
    let unknown = Set(values.keys).subtracting(["account", "path", "query", "body"])
    guard unknown.isEmpty else { throw HackerRankError.http(0, "Unknown argument: \(unknown.sorted().joined(separator: ", "))") }
    let request = Value.object(values.filter { $0.key != "account" })
    let value = try JSONDecoder().decode(HackerRankJSONValue.self, from: JSONEncoder().encode(request))
    return try HackerRankAPIInputs(value: value)
}

extension HackerRankProvider {
    func callFullAPI(_ name: String, arguments: [String: Value]?) async -> CallTool.Result {
        do {
            guard let operation = try HackerRankClient.apiCatalogue().operations.first(where: { $0.id == name }) else {
                return errorResult("Unknown tool: \(name)")
            }
            guard allowWrites || !operation.isWrite else {
                return errorResult("Write tools are disabled. Enable HACKERRANK_MCP_ALLOW_WRITES to use this operation.")
            }
            let requested: String?
            if let value = arguments?["account"] {
                guard case let .string(text) = value else { return errorResult("account must be a string") }
                requested = text
            } else {
                requested = nil
            }
            guard let account = accountSet.resolve(requested) else { return errorResult("Unknown HackerRank account") }
            let input = try fullAPIInputs(arguments)
            let client = try await clientCache.client(for: account)
            let result = try await client.executeAPI(
                name, pathParameters: input.pathParameters, query: input.query, body: input.body,
                scimToken: account.scimToken
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return CallTool.Result(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)])
        } catch let HackerRankError.http(0, message) {
            return errorResult(message)
        } catch {
            return errorResult(toolErrorMessage(error))
        }
    }
}

/// Parses the standalone server's explicit write setting without treating arbitrary text as true.
public func hackerRankMCPWritesEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Bool {
    switch environment["HACKERRANK_MCP_ALLOW_WRITES"]?.lowercased() {
    case nil, "0", "false": return false
    case "1", "true": return true
    default: throw HackerRankMCPConfigError.invalidConfig("HACKERRANK_MCP_ALLOW_WRITES must be true, false, 1 or 0")
    }
}
