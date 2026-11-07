// swift-tools-version: 6.4
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
        .package(url: "https://github.com/adamtheturtle/MCPKit.git", exact: "0.6.0"),
        .package(url: "https://github.com/adamtheturtle/HackerRankKit.git", revision: "efdd68ae2750f7a6f835be1a430406392a35b9f8"),
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
        .testTarget(
            name: "HackerRankMCPTests",
            dependencies: [
                "HackerRankMCP",
                .product(name: "HackerRankKitMock", package: "HackerRankKit"),
            ]
        ),
    ]
)
