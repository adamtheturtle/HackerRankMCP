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
