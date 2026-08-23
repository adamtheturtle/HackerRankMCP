import Foundation
import HackerRankKit
import HackerRankKitMock
import Testing

struct MockIntegrationTests {
    @Test func `mock server serves paginated tests`() async throws {
        let client = HackerRankClient.mock(key: "hrmcp-\(UUID().uuidString)")
        let page = try await client.testsPage(after: nil)
        #expect(!page.items.isEmpty)
        #expect(page.items[0].id.isEmpty == false)
    }

    @Test func `mock server serves candidates for a test`() async throws {
        let client = HackerRankClient.mock(key: "hrmcp-\(UUID().uuidString)")
        let tests = try await client.testsPage(after: nil)
        let testID = try #require(tests.items.first?.id)
        let candidates = try await client.candidatesPage(testID: testID, after: nil)
        #expect(!candidates.items.isEmpty)
    }
}
