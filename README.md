# HackerRankMCP

An unofficial, embeddable Model Context Protocol provider and standalone server for the HackerRank for Work REST API.

HackerRankMCP exposes every documented HackerRank for Work API operation, including ATS integrations and SCIM provisioning.
Read tools are enabled by default.
Writes require explicit configuration.
Credentials remain in the host application or the standalone server's environment/configuration file and are never returned to clients.

## Installation

```swift
.package(
    url: "https://github.com/adamtheturtle/HackerRankMCP.git",
    from: "0.1.1"
)
```

Add the `HackerRankMCP` product to an application target, or install and run the bundled `hackerrank-mcp` executable.

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

- Write tools require `HACKERRANK_MCP_ALLOW_WRITES=true`, or `allowWrites: true` when embedding.
- Tokens are never included in MCP results.
- Custom base URLs must use HTTPS and cannot contain credentials.
- SCIM uses `HACKERRANK_SCIM_API_TOKEN`, or an account-specific `scim_token` in the JSON configuration.
- Provisioning credentials are separate from ordinary API tokens and are never returned in results.

## Requirements

- Swift 6.4+
- macOS 15+

## License

MIT.
See [LICENSE](LICENSE).

## Project AI prompts

`list_questions` includes `custom_system_prompt` when HackerRank returns it.
An empty string is preserved, and an absent value appears as JSON null.
Enable writes and use `api_update_question` to set the prompt in the request body.

## Read coverage

The provider exposes all documented v3 read routes: resource details, global candidate search, per-test candidate search, user search, team memberships, test inviters, invite and interview templates, interview transcripts, Interviews V2 artifacts and notes, and offset/cursor audit logs.
New read tools preserve the complete API JSON response and pagination metadata.
Artifact reads distinguish available metadata from the pending response and retry delay.
The `api_` catalogue adds all 76 operations, including writes and SCIM provisioning.
Each tool accepts nested `path`, `query` and `body` objects with schemas generated from the official contract.
Responses retain HTTP status, headers and JSON, including empty and pending results.

This branch temporarily pins the HackerRankKit commit from [HackerRankKit #224](https://github.com/adamtheturtle/HackerRankKit/pull/224).
Replace that revision with a released version after the SDK is released.
