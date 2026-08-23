import HackerRankKit
@testable import HackerRankMCP
import Testing

struct SanitizeErrorsTests {
    @Test func `HTTP errors omit response bodies`() {
        let message = toolErrorMessage(HackerRankError.http(502, #"{"secret":"token"}"#))
        #expect(message.contains("502"))
        #expect(!message.contains("secret"))
    }
}
