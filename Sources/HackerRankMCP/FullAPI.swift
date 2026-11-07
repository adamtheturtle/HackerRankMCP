import Foundation
import HackerRankKit
import MCP

func fullAPIDescriptors(allowWrites: Bool) -> [[String: Any]] {
    APIDescriptorCache.all.filter { allowWrites || ($0["annotations"] as? [String: Bool])?["readOnlyHint"] == true }
}

private enum APIDescriptorCache {
    /// JSON-only value dictionaries are initialized once and never mutated or exposed by reference.
    nonisolated(unsafe) static let all = makeFullAPIDescriptors()
}

private func makeFullAPIDescriptors() -> [[String: Any]] {
    guard let catalogue = try? HackerRankClient.apiCatalogue() else { return [] }

    return catalogue.operations.compactMap { operation in
        guard case var .object(schema) = catalogue.inputSchema(for: operation),
              case var .object(properties)? = schema["properties"] else { return nil }

        properties["account"] = .object(["type": .string("string")])
        schema["properties"] = .object(properties)
        guard let data = try? JSONEncoder().encode(HackerRankJSONValue.object(schema)),
              let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        return [
            "name": operation.id, "description": "\(operation.summary) (\(operation.method) \(operation.path)).",
            "annotations": ["readOnlyHint": !operation.isWrite], "inputSchema": input
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

/// Parses the standalone server's explicit write setting without treating arbitrary text as true.
public func hackerRankMCPWritesEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Bool {
    switch environment["HACKERRANK_MCP_ALLOW_WRITES"]?.lowercased() {
    case nil, "0", "false": return false
    case "1", "true": return true
    default: throw HackerRankMCPConfigError.invalidConfig("HACKERRANK_MCP_ALLOW_WRITES must be true, false, 1 or 0")
    }
}
