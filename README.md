# HackerRankMCP

An unofficial, embeddable Model Context Protocol provider and standalone server for
the HackerRank for Work REST API.

HackerRankMCP gives assistants read-only access to tests, questions, interviews,
candidates, users, and teams. Credentials remain in the host application or the
standalone server's environment/configuration file and are never returned to clients.

## Installation

```swift
.package(
    url: "https://github.com/adamtheturtle/HackerRankMCP.git",
    from: "0.1.1"
)
```

Add the `HackerRankMCP` product to an application target, or install and run the
bundled `hackerrank-mcp` executable.

## Embedding

```swift
import HackerRankMCP
import MCPKit

let account = HackerRankMCPAccount(name: "Work", token: token)
let accounts = try HackerRankMCPAccountSet(accounts: [account])
let provider = HackerRankProvider(accountSet: accounts)
let server = MCPServer(
    name: "My HackerRank integration",
    version: "1.0.0",
    provider: provider
)
```

## Standalone server

```sh
HACKERRANK_API_TOKEN=your-token swift run hackerrank-mcp
```

Optional variables:

- `HACKERRANK_ACCOUNT_NAME`
- `HACKERRANK_BASE_URL` (HTTPS only)
- `HACKERRANK_MCP_CONFIG`

The JSON configuration format supports multiple accounts:

```json
{
  "accounts": [
    {
      "name": "Work",
      "token": "secret",
      "base_url": "https://www.hackerrank.com",
      "default": true
    }
  ]
}
```

## Products

- `HackerRankMCP`: account configuration and reusable ``HackerRankProvider``.
- `hackerrank-mcp`: stdio server for editors, agents, and MCP clients.

## Security

- Every advertised tool is read-only.
- Tokens are never included in MCP results.
- Custom base URLs must use HTTPS and cannot contain credentials.
- The package provides no create, update, archive, or delete tools.

## Requirements

- Swift 6.2+
- macOS 15+

## License

MIT. See [LICENSE](LICENSE).
