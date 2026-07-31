// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HackerRankMCP",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HackerRankMCP", targets: ["HackerRankMCP"]),
        .executable(name: "hackerrank-mcp", targets: ["hackerrank-mcp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        .package(url: "https://github.com/adamtheturtle/MCPKit.git", exact: "0.1.0"),
        .package(url: "https://github.com/adamtheturtle/HackerRankKit.git", exact: "0.4.0"),
    ],
    targets: [
        .target(
            name: "HackerRankMCP",
            dependencies: [
                .product(name: "HackerRankKit", package: "HackerRankKit"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "MCPKit", package: "MCPKit"),
            ]
        ),
        .executableTarget(
            name: "hackerrank-mcp",
            dependencies: [
                "HackerRankMCP",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "MCPKit", package: "MCPKit"),
            ]
        ),
        .testTarget(name: "HackerRankMCPTests", dependencies: ["HackerRankMCP"]),
    ]
)
