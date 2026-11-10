import Foundation
import HackerRankKit
import HackerRankMCP
import MCP
import MCPKit

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--version"] {
        print(hackerRankMCPVersion)
        exit(0)
    }
    if arguments == ["--check-installation"] {
        let catalogue = try HackerRankClient.apiCatalogue()
        print("HackerRank MCP \(hackerRankMCPVersion): \(catalogue.operations.count) API operations available.")
        exit(0)
    }
    if arguments == ["--help"] || arguments == ["-h"] {
        print("Usage: hackerrank-mcp [--version | --check-installation | --help]")
        print("Without arguments, start the authenticated MCP server on standard input/output.")
        exit(0)
    }
    guard arguments.isEmpty else {
        throw NSError(domain: "HackerRankMCP", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Unknown arguments. Run hackerrank-mcp --help for usage."
        ])
    }
    let accounts = try loadHackerRankMCPAccounts()
    try await validateHackerRankAccountsOnStartup(accounts)
    let provider = HackerRankProvider(accountSet: accounts, allowWrites: try hackerRankMCPWritesEnabled())
    let server = MCPServer(
        name: "HackerRank MCP",
        version: hackerRankMCPVersion,
        capabilities: .init(tools: .init(listChanged: false)),
        provider: provider
    )
    try await server.run(transport: StdioTransport())
} catch {
    FileHandle.standardError.write(Data("hackerrank-mcp: \(error.localizedDescription)\n".utf8))
    exit(1)
}
