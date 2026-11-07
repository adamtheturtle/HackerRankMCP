import Foundation

// Input constraints for the shared friendly write tools.

nonisolated enum TestNameValidation {
    static let maxLength = 255

    static func isValid(_ name: String) -> Bool {
        !name.isEmpty && name.count <= maxLength
    }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canSubmit(_ name: String, currentName: String?) -> Bool {
        let normalizedName = normalized(name)
        guard isValid(normalizedName) else { return false }

        return currentName.map(normalized) != normalizedName
    }
}

nonisolated enum TestScheduleValidation {
    static func error(startTime: String, endTime: String) -> String? {
        let start = normalizedDate(startTime)
        let end = normalizedDate(endTime)
        if !startTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, start == nil {
            return "Start time must be an ISO-8601 timestamp."
        }
        if !endTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, end == nil {
            return "End time must be an ISO-8601 timestamp."
        }
        if let start, let end, end <= start {
            return "End time must be after start time."
        }
        return nil
    }

    private static func normalizedDate(_ value: String) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }
}

enum EmailValidation {
    private static let localCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!#$%&'*+-/=?^_`{|}~"
    )
    private static let domainCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"
    )

    /// Whether `raw` looks like a plausible email: after trimming, exactly one `@`, a
    /// conservatively valid local part, and a dotted DNS-style domain.
    static func isLikelyValid(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }

        let local = parts[0]
        let domain = parts[1]
        guard
            !local.isEmpty,
            local.unicodeScalars.allSatisfy(localCharacters.contains),
            !local.hasPrefix("."),
            !local.hasSuffix("."),
            !local.contains(".."),
            domain.unicodeScalars.allSatisfy(domainCharacters.contains)
        else {
            return false
        }

        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy {
            !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasSuffix("-")
        }
    }
}

enum CandidateInviteValidation {
    struct TextFields {
        var fullName: String?
        var tags: [String]?
        var evaluatorEmail: String?
        var emailSubject: String?
        var emailMessage: String?
        var atsCandidateID: String?
        var atsRequisitionID: String?
    }

    /// One day is a generous accommodation ceiling while preventing accidental pasted magnitudes.
    static let additionalTimeRange = 0 ... 1440
    nonisolated static let maxFullNameLength = 255
    nonisolated static let maxTagLength = 100
    nonisolated static let maxTagCount = 50
    static let maxEmailLength = 320
    static let maxIdentifierLength = 255
    static let maxSubjectLength = 255
    static let maxMessageLength = 10000

    static func isValid(additionalTime: Int?) -> Bool {
        additionalTime.map(additionalTimeRange.contains) ?? true
    }

    static func validityOrderIssue(validFrom: String?, validUntil: String?) -> String? {
        guard
            let validFrom,
            let validUntil,
            let start = parsedTimestamp(validFrom),
            let end = parsedTimestamp(validUntil),
            end <= start
        else {
            return nil
        }

        return "Valid until must be later than Valid from."
    }

    static func validityTimestampIssue(validFrom: String?, validUntil: String?) -> String? {
        if let validFrom, parsedTimestamp(validFrom) == nil {
            return "Valid from must be an ISO-8601 timestamp."
        }
        if let validUntil, parsedTimestamp(validUntil) == nil {
            return "Valid until must be an ISO-8601 timestamp."
        }
        return nil
    }

    static func normalizedFullName(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func fullNameIssue(_ value: String?) -> String? {
        guard let value, value.count > maxFullNameLength else { return nil }

        return "Full name can be at most \(maxFullNameLength) characters."
    }

    static func textIssue(_ fields: TextFields) -> String? {
        if let issue = fullNameIssue(fields.fullName) {
            return issue
        }
        if let tags = fields.tags, tags.count > maxTagCount {
            return "Use at most \(maxTagCount) tags."
        }
        if let tag = fields.tags?.first(where: { $0.count > maxTagLength }) {
            return "Tag “\(tag.prefix(20))” exceeds \(maxTagLength) characters."
        }
        if let evaluatorEmail = fields.evaluatorEmail, evaluatorEmail.count > maxEmailLength {
            return "Evaluator email can be at most \(maxEmailLength) characters."
        }
        if let emailSubject = fields.emailSubject, emailSubject.count > maxSubjectLength {
            return "Email subject can be at most \(maxSubjectLength) characters."
        }
        if let emailMessage = fields.emailMessage, emailMessage.count > maxMessageLength {
            return "Email message can be at most \(maxMessageLength.formatted()) characters."
        }
        if let atsCandidateID = fields.atsCandidateID, atsCandidateID.count > maxIdentifierLength {
            return "ATS candidate ID can be at most \(maxIdentifierLength) characters."
        }
        if let atsRequisitionID = fields.atsRequisitionID, atsRequisitionID.count > maxIdentifierLength {
            return "ATS requisition ID can be at most \(maxIdentifierLength) characters."
        }
        return nil
    }

    private static func parsedTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }
}

nonisolated enum UserNameValidation {
    static let maxLength = 255

    static func firstNameIssue(_ value: String) -> String? {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "First name is required."
        }

        return value.count > maxLength ? "First name can be at most \(maxLength) characters." : nil
    }

    static func lastNameIssue(_ value: String?) -> String? {
        guard let value, value.count > maxLength else { return nil }

        return "Last name can be at most \(maxLength) characters."
    }

    static func issue(firstName: String, lastName: String?) -> String? {
        if let issue = firstNameIssue(firstName) {
            return issue
        }
        if let issue = lastNameIssue(lastName) {
            return issue
        }
        return nil
    }
}

nonisolated enum QuestionEditValidation {
    static let maxSystemPromptLength = 15000

    static func systemPromptIssue(_ prompt: String) -> String? {
        prompt.unicodeScalars.count > maxSystemPromptLength
            ? "Custom system prompt must be at most 15,000 characters." : nil
    }

    static let recommendedDurationRange = 0 ... 1440

    static func maxScore(from text: String) -> Double? {
        guard let value = Double(text), value.isFinite, value >= 0 else { return nil }

        return value
    }

    static func isValidRecommendedDuration(_ value: Int?) -> Bool {
        value.map(recommendedDurationRange.contains) ?? true
    }
}

nonisolated enum TeamNameValidation {
    static let maxLength = 255

    static func isValid(_ name: String) -> Bool {
        !name.isEmpty && name.count <= maxLength
    }
}

nonisolated enum PadTitleValidation {
    static let maxLength = 255

    static func normalized(_ title: String?) -> String? {
        guard let title else { return nil }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return String(trimmed.prefix(maxLength))
    }
}

nonisolated enum InterviewScheduleValidation {
    static let maxTitleLength = 255
    static let maxEmailLength = 320
    static let maxNotesLength = 10000

    static func titleIssue(_ title: String) -> String? {
        title.count > maxTitleLength ? "Title can be at most \(maxTitleLength) characters." : nil
    }

    static func notesIssue(_ notes: String?) -> String? {
        guard let notes, notes.count > maxNotesLength else { return nil }

        return "Notes can be at most \(maxNotesLength.formatted()) characters."
    }

    static func textIssue(title: String, candidateEmail: String?, notes: String?) -> String? {
        if let issue = titleIssue(title) {
            return issue
        }
        if let candidateEmail, candidateEmail.count > maxEmailLength {
            return "Candidate email can be at most \(maxEmailLength) characters."
        }
        if let issue = notesIssue(notes) {
            return issue
        }
        return nil
    }

    static func dateIssue(start: Date, now: Date = Date()) -> String? {
        start > now ? nil : "Start time must be in the future."
    }
}
