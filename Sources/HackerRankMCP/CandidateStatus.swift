func candidateStatusLabel(_ status: Int?) -> String? {
    guard let status else { return nil }
    switch status {
    case 0: return "invited"
    case 1: return "registration_started"
    case 2: return "registered"
    case 3: return "not_logged_in"
    case 4: return "logged_in"
    case 5: return "test_in_progress"
    case 6: return "test_completed"
    case 7: return "test_submitted"
    case 8: return "test_timed_out"
    case 9: return "test_aborted"
    default: return "unknown"
    }
}


// The embedded tools preserve RankBuddy's human-readable pipeline and attempt labels.
func candidateStatusLabel(_ status: Int?, atsState: Int?) -> String? {
    switch atsState {
    case 1: return "Test completed: evaluation required"
    case 2: return "Test completed: qualified"
    case 3: return "Test completed: failed"
    case 7: return "Offer sent"
    case 8: return "Offer negotiation"
    case 9: return "Offer accepted"
    case 10: return "Offer declined"
    case 11: return "On hold"
    case 12: return "Phone interview: cleared"
    case 13: return "Phone interview: failed"
    case 14: return "Technical interview: cleared"
    case 15: return "Technical interview: failed"
    case 16: return "HR interview: cleared"
    case 17: return "HR interview: failed"
    case 21: return "Hired"
    case 22: return "Rejected"
    default: break
    }
    switch status {
    case -1: return "Invited"
    case 0: return "In progress"
    case 1: return "Completed (reports pending)"
    case 7: return "Reports ready"
    default: return nil
    }
}
