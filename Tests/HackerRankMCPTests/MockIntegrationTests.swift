import Foundation
import HackerRankKit
import HackerRankKitMock
import Testing

struct MockIntegrationTests {
    @Test func `mock server serves paginated tests`() async throws {
        let client = await MainActor.run { HackerRankClient.mock(key: "hrmcp-\(UUID().uuidString)") }
        let page = try await client.testsPage(after: nil)
        #expect(!page.items.isEmpty)
        #expect(page.items[0].id.isEmpty == false)
    }

    @Test func `mock server serves candidates for a test`() async throws {
        let client = await MainActor.run { HackerRankClient.mock(key: "hrmcp-\(UUID().uuidString)") }
        let tests = try await client.testsPage(after: nil)
        let testID = try #require(tests.items.first?.id)
        let candidates = try await client.candidatesPage(testID: testID, after: nil)
        #expect(!candidates.items.isEmpty)
    }

    @Test func `mock server team rows include interviewer count`() async throws {
        let client = await MainActor.run { HackerRankClient.mock(key: "hrmcp-\(UUID().uuidString)") }
        let page = try await client.teamsPage(after: nil)
        let team = try #require(page.items.first)
        #expect(team.interviewerCount == 2)
    }
}
