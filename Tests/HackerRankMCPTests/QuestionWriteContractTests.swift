import Foundation
import HackerRankKit
@testable import HackerRankMCP
import MCP
import Testing

@MainActor
struct QuestionWriteContractTests {
    private func provider(
        type: String = "fullstack", mode: String = "valid", allowWrites: Bool = true
    ) throws -> (HackerRankToolProvider, QuestionRequestRecorder) {
        let token = "synthetic-\(UUID().uuidString)"
        let account = HackerRankMCPAccount(name: "Test", token: token)
        let recorder = QuestionRequestRecorder(type: type, mode: mode)
        QuestionRecordingProtocol.register(token: token, recorder: recorder)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QuestionRecordingProtocol.self]
        let session = URLSession(configuration: config)
        let provider = HackerRankToolProvider(allowWrites: allowWrites, context: {
            HackerRankMCPContext(accounts: [account], currentAccountID: account.id)
        }, makeClient: { account in
            try await HackerRankClient(token: account.token, session: session)
        })
        return (provider, recorder)
    }

    @Test
    func schemasUseTheSDKTypes() async throws {
        let (provider, _) = try provider()
        for name in ["create_question", "update_question"] {
            let tool = try #require(await provider.tools().first { $0.name == name })
            let schema = try JSONDecoder().decode(
                HackerRankJSONValue.self,
                from: JSONEncoder().encode(tool.inputSchema)
            )
            guard case let .object(root) = schema,
                  case let .object(properties) = root["properties"],
                  case let .object(type) = properties["type"],
                  case let .array(values) = type["enum"] else {
                Issue.record("Expected the friendly question-type schema")
                return
            }
            #expect(Set(values) == Set(QuestionType.allCases.map { .string($0.rawValue) }))
        }
    }

    @Test(arguments: QuestionType.allCases)
    func createsKnownTypesWithoutLegacyAliases(_ type: QuestionType) async throws {
        let (provider, recorder) = try provider()
        let result = await provider.callTool("create_question", arguments: [
            "name": .string("Question"), "type": .string(type.rawValue),
            "problem_statement": .string("Build it."), "recommended_duration": .int(0)
        ])
        #expect(result.isError != true)
        #expect(recorder.requests.map(\.httpMethod) == ["POST"])
        #expect(try recorder.lastBody()["type"] == .string(type.rawValue))
        #expect(recorder.requests.first?.url?.absoluteString == "https://www.hackerrank.com/x/api/v3/questions/")
    }

    @Test(arguments: ["coding", "subjective"])
    func legacyAliasesAreRejectedBeforeRequests(_ type: String) async throws {
        let (provider, recorder) = try provider()
        let created = await provider.callTool("create_question", arguments: [
            "name": .string("Question"), "type": .string(type),
            "problem_statement": .string("Build it."), "recommended_duration": .int(1)
        ])
        let updated = await provider.callTool("update_question", arguments: [
            "question_id": .string("q1"), "type": .string(type)
        ])
        #expect(created.isError == true)
        #expect(updated.isError == true)
        #expect(recorder.requests.isEmpty)
    }

    @Test
    func textAnswerNormalizationKeepsTheAPISpelling() async throws {
        let (provider, recorder) = try provider()
        let result = await provider.callTool("update_question", arguments: [
            "question_id": .string("q1"), "type": .string(" TEXTANS ")
        ])
        #expect(result.isError != true)
        #expect(try recorder.lastBody()["type"] == .string("textAns"))
    }

    @Test(arguments: [false, true])
    func selectedUpdatesPreserveMetadataAndStringAnswers(_ clearLanguages: Bool) async throws {
        let (provider, recorder) = try provider()
        var arguments: [String: Value] = [
            "question_id": .string("q1"), "name": .string("Renamed"),
            "tags": .array([]), "custom_system_prompt": .string("")
        ]
        if clearLanguages { arguments["languages"] = .array([]) }
        let result = await provider.callTool("update_question", arguments: arguments)
        #expect(result.isError != true)
        #expect(recorder.requests.map(\.httpMethod) == ["GET", "PUT"])
        #expect(try recorder.lastBody() == [
            "name": .string("Renamed"), "type": .string("fullstack"),
            "internal_notes": .string(" Keep notes.\n"),
            "languages": clearLanguages ? .array([]) : .array([.string("python3")]),
            "problem_statement": .string("Keep statement"), "recommended_duration": .int(0),
            "tags": .array([]), "options": .array([.string("choice")]), "answer": .string("0"),
            "custom_system_prompt": .string("")
        ])
        #expect(recorder.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer synthetic-") == true
        })
    }

    @Test(arguments: ["code", "whiteboard"])
    func unsupportedKnownPromptsAreLocal(_ type: String) async throws {
        let (provider, recorder) = try provider()
        let create = await provider.callTool("create_question", arguments: [
            "name": .string("Question"), "type": .string(type), "problem_statement": .string("Choose"),
            "recommended_duration": .int(1), "custom_system_prompt": .string("")
        ])
        let update = await provider.callTool("update_question", arguments: [
            "question_id": .string("q1"), "type": .string(type), "custom_system_prompt": .string("")
        ])
        #expect(create.isError == true)
        #expect(update.isError == true)
        #expect(recorder.requests.isEmpty)
    }

    @Test
    func omittedTypeUsesTheReadQuestionCapability() async throws {
        let (provider, recorder) = try provider(type: "code")
        let result = await provider.callTool("update_question", arguments: [
            "question_id": .string("q1"), "custom_system_prompt": .string("")
        ])
        #expect(result.isError == true)
        #expect(recorder.requests.map(\.httpMethod) == ["GET"])
    }

    @Test(arguments: ["missing", "malformed", "forbidden"])
    func failedReadsNeverMutate(_ mode: String) async throws {
        let (provider, recorder) = try provider(mode: mode)
        let result = await provider.callTool("update_question", arguments: [
            "question_id": .string("q1"), "name": .string("Renamed")
        ])
        #expect(result.isError == true)
        #expect(recorder.requests.map(\.httpMethod) == ["GET"])
    }

    @Test
    func hiddenWriteToolsStayDisabled() async throws {
        let (provider, recorder) = try provider(allowWrites: false)
        #expect(await provider.tools().allSatisfy { $0.annotations.readOnlyHint == true })
        let friendly = await provider.callTool("update_question", arguments: [
            "question_id": .string("q1"), "name": .string("Renamed")
        ])
        let canonical = await provider.callTool("api_update_question", arguments: [
            "path": .object(["question_id": .string("q1")]), "body": .object(["name": .string("Renamed")])
        ])
        #expect(friendly.isError == true)
        #expect(canonical.isError == true)
        #expect(recorder.requests.isEmpty)
    }

    @Test
    func genericToolsRetainUnknownFutureTypes() async throws {
        let (provider, recorder) = try provider()
        let result = await provider.callTool("api_update_question", arguments: [
            "path": .object(["question_id": .string("q1")]),
            "body": .object(["type": .string("future_type"), "custom_system_prompt": .string("Hints")])
        ])
        #expect(result.isError != true)
        #expect(recorder.requests.map(\.httpMethod) == ["PUT"])
        #expect(try recorder.lastBody()["type"] == .string("future_type"))
    }
}

private final class QuestionRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var bodies: [Data] = []
    let type: String
    let mode: String

    init(type: String, mode: String) {
        self.type = type; self.mode = mode
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func lastBody() throws -> [String: HackerRankJSONValue] {
        let body = try #require(lock.withLock { bodies.last })
        return try JSONDecoder().decode([String: HackerRankJSONValue].self, from: body)
    }

    func respond(_ request: URLRequest) -> (Int, Data) {
        let body = Self.body(request)
        lock.withLock { recorded.append(request); bodies.append(body) }
        guard request.httpMethod == "GET" else {
            return request.httpMethod == "POST" ? (201, Data(#"{"id":"created"}"#.utf8)) : (204, Data())
        }
        if mode == "forbidden" { return (403, Data()) }
        var snapshot: [String: HackerRankJSONValue] = [
            "id": .string("q1"), "name": .string("Current"), "type": .string(type),
            "problem_statement": .string("Keep statement"), "recommended_duration": .int(0),
            "internal_notes": .string(" Keep notes.\n"), "languages": .array([.string("python3")]),
            "tags": .array([.string("tag")]), "options": .array([.string("choice")]), "answer": .string("0"),
            "environment_id": .int(112), "custom_system_prompt": .string("Keep prompt")
        ]
        if mode == "missing" { snapshot.removeValue(forKey: "recommended_duration") }
        if mode == "malformed" { snapshot["answer"] = .object([:]) }
        do { return (200, try JSONEncoder().encode(snapshot)) } catch { return (500, Data()) }
    }

    private static func body(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            body.append(buffer, count: count)
        }
        return body
    }
}

private final class QuestionRecordingProtocol: URLProtocol, @unchecked Sendable {
    private nonisolated(unsafe) static var recorders: [String: QuestionRequestRecorder] = [:]
    private static let lock = NSLock()

    static func register(token: String, recorder: QuestionRequestRecorder) {
        lock.withLock { recorders[token] = recorder }
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func stopLoading() {}

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: "Authorization")?
            .replacingOccurrences(of: "Bearer ", with: "") ?? ""
        guard let recorder = Self.lock.withLock({ Self.recorders[token] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (status, data) = recorder.respond(request)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])
            else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
