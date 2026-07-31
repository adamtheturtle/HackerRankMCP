import Foundation
import HackerRankMCP
import MCP
import MCPKit

do {
    let accounts = try loadHackerRankMCPAccounts()
    let provider = HackerRankProvider(accountSet: accounts)
    let server = MCPServer(name: "HackerRank MCP", version: hackerRankMCPVersion, provider: provider)
    try await server.run(transport: StdioTransport())
} catch {
    FileHandle.standardError.write(Data("hackerrank-mcp: \(error.localizedDescription)\n".utf8))
    exit(1)
}
