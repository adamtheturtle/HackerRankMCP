@testable import HackerRankMCP
import Testing

struct CandidateStatusTests {
    @Test func `candidate status labels map known codes`() {
        #expect(candidateStatusLabel(7) == "test_submitted")
        #expect(candidateStatusLabel(0) == "invited")
        #expect(candidateStatusLabel(nil) == nil)
        #expect(candidateStatusLabel(999) == "unknown")
    }
}
