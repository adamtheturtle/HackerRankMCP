import Foundation

public struct HackerRankMCPAccount: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var token: String
    public var baseURL: URL

    public init(
        id: UUID = UUID(),
        name: String,
        token: String,
        baseURL: URL = URL(string: "https://www.hackerrank.com")!
    ) {
        self.id = id
        self.name = name
        self.token = token
        self.baseURL = baseURL
    }
}

public struct HackerRankMCPAccountSet: Sendable {
    public let accounts: [HackerRankMCPAccount]
    public let defaultAccountID: UUID

    public init(accounts: [HackerRankMCPAccount], defaultAccountID: UUID? = nil) throws {
        guard let first = accounts.first else { throw HackerRankMCPConfigError.noAccounts }
        for account in accounts {
            let trimmed = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw HackerRankMCPConfigError.blankAccountName }
        }
        let names = accounts.map { $0.name.lowercased() }
        guard Set(names).count == names.count else { throw HackerRankMCPConfigError.duplicateNames }
        let selected = defaultAccountID ?? first.id
        guard accounts.contains(where: { $0.id == selected }) else {
            throw HackerRankMCPConfigError.invalidDefaultAccount
        }
        self.accounts = accounts
        self.defaultAccountID = selected
    }

    public func resolve(_ requested: String?) -> HackerRankMCPAccount? {
        guard let requested, !requested.isEmpty else {
            return accounts.first { $0.id == defaultAccountID }
        }
        return accounts.first {
            $0.name.localizedCaseInsensitiveCompare(requested) == .orderedSame
                || $0.id.uuidString.localizedCaseInsensitiveCompare(requested) == .orderedSame
        }
    }
}

public enum HackerRankMCPConfigError: LocalizedError, Equatable {
    case noAccounts
    case duplicateNames
    case invalidDefaultAccount
    case invalidBaseURL(String)
    case invalidConfig(String)
    case invalidToken(String)
    case startupValidationFailed(String, String)
    case multipleDefaults
    case blankAccountName
    case emptyToken(String)

    public var errorDescription: String? {
        switch self {
        case .noAccounts: "No HackerRank accounts are configured."
        case .duplicateNames: "HackerRank account names must be unique."
        case .invalidDefaultAccount: "The default HackerRank account is not configured."
        case let .invalidBaseURL(value): "Unsupported HackerRank base URL: \(value)"
        case let .invalidConfig(detail): "Invalid HackerRank MCP config: \(detail)"
        case let .invalidToken(name): "HackerRank account \"\(name)\" has an invalid API token."
        case let .startupValidationFailed(name, detail):
            "Could not validate HackerRank account \"\(name)\": \(detail)"
        case .multipleDefaults: "Only one HackerRank account may be marked as default."
        case .blankAccountName: "HackerRank account names must not be blank."
        case let .emptyToken(name): "HackerRank account \"\(name)\" has an empty API token."
        }
    }
}

private struct ConfigFile: Decodable {
    struct Account: Decodable {
        let name: String
        let token: String
        let baseURL: String?
        let isDefault: Bool?

        enum CodingKeys: String, CodingKey {
            case name, token
            case baseURL = "base_url"
            case isDefault = "default"
        }
    }

    let accounts: [Account]
}

public func loadHackerRankMCPAccounts(
    environment: [String: String] = ProcessInfo.processInfo.environment
) throws -> HackerRankMCPAccountSet {
    if let path = environment["HACKERRANK_MCP_CONFIG"], !path.isEmpty {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            return try loadAccounts(fromConfigFileAt: url)
        }
    }

    if let token = environment["HACKERRANK_API_TOKEN"] {
        guard !token.isEmpty else { throw HackerRankMCPConfigError.emptyToken("HackerRank") }
        let baseURL = try validatedBaseURL(environment["HACKERRANK_BASE_URL"])
        let name = environment["HACKERRANK_ACCOUNT_NAME"] ?? "HackerRank"
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw HackerRankMCPConfigError.blankAccountName }
        return try HackerRankMCPAccountSet(accounts: [
            HackerRankMCPAccount(name: trimmedName, token: token, baseURL: baseURL),
        ])
    }
    throw HackerRankMCPConfigError.noAccounts
}

private func loadAccounts(fromConfigFileAt url: URL) throws -> HackerRankMCPAccountSet {
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw HackerRankMCPConfigError.invalidConfig("could not read \(url.path): \(error.localizedDescription)")
    }

    let config: ConfigFile
    do {
        config = try JSONDecoder().decode(ConfigFile.self, from: data)
    } catch let error as DecodingError {
        throw HackerRankMCPConfigError.invalidConfig(decodingErrorDescription(error))
    } catch {
        throw HackerRankMCPConfigError.invalidConfig(error.localizedDescription)
    }

    var defaultID: UUID?
    var sawDefault = false
    let accounts = try config.accounts.map { item in
        let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw HackerRankMCPConfigError.blankAccountName }
        guard !item.token.isEmpty else { throw HackerRankMCPConfigError.emptyToken(trimmedName) }
        let baseURL = try validatedBaseURL(item.baseURL)
        let account = HackerRankMCPAccount(name: trimmedName, token: item.token, baseURL: baseURL)
        if item.isDefault == true {
            if sawDefault { throw HackerRankMCPConfigError.multipleDefaults }
            sawDefault = true
            defaultID = account.id
        }
        return account
    }
    return try HackerRankMCPAccountSet(accounts: accounts, defaultAccountID: defaultID)
}

private func decodingErrorDescription(_ error: DecodingError) -> String {
    switch error {
    case let .keyNotFound(key, context):
        let path = codingPath(context.codingPath + [key])
        return "missing required field \(path)"
    case let .typeMismatch(type, context):
        return "expected \(type) at \(codingPath(context.codingPath))"
    case let .valueNotFound(type, context):
        return "expected \(type) at \(codingPath(context.codingPath)) but found null"
    case let .dataCorrupted(context):
        if context.codingPath.isEmpty {
            return context.debugDescription.isEmpty ? "malformed JSON" : context.debugDescription
        }
        return "invalid value at \(codingPath(context.codingPath)): \(context.debugDescription)"
    @unknown default:
        return error.localizedDescription
    }
}

private func codingPath(_ path: [CodingKey]) -> String {
    guard !path.isEmpty else { return "(root)" }
    return path.map(\.stringValue).joined(separator: ".")
}

private func validatedBaseURL(_ value: String?) throws -> URL {
    guard let value, !value.isEmpty else {
        return URL(string: "https://www.hackerrank.com")!
    }
    guard let url = URL(string: value),
          url.scheme?.lowercased() == "https",
          let host = url.host,
          !host.isEmpty,
          url.user == nil,
          url.password == nil,
          url.query == nil,
          url.fragment == nil
    else {
        throw HackerRankMCPConfigError.invalidBaseURL(value)
    }

    let path = url.path
    if path != "" && path != "/" {
        throw HackerRankMCPConfigError.invalidBaseURL(value)
    }
    if value.hasSuffix("/") {
        throw HackerRankMCPConfigError.invalidBaseURL(value)
    }
    let normalizedHost = host.lowercased()
    if normalizedHost == "127.0.0.1" || normalizedHost == "localhost" || normalizedHost == "::1" {
        throw HackerRankMCPConfigError.invalidBaseURL(value)
    }

    return url
}
