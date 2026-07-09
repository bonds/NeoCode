import SwiftUI

struct SubagentTaskCardView: View {
    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime
    @Environment(\.locale) private var locale
    @State private var fetchedSubagentID: String?

    let toolCall: ChatMessage.ToolCall

    private var sessionID: String? { store.selectedSessionID }

    private var subagentSessions: [SessionSummary] {
        guard let sessionID, let project = store.projects.first(where: { $0.sessions.contains(where: { $0.id == sessionID }) })
        else { return [] }
        return project.childSessions(for: sessionID)
    }

    var body: some View {
        let subagents = subagentSessions

        VStack(alignment: .leading, spacing: 12) {
            if subagents.isEmpty {
                taskToolCard
            } else {
                ForEach(subagents) { subagent in
                    subagentCard(subagent)
                }
            }
        }
        .task {
            guard let sessionID else { return }
            await store.syncChildSessions(for: sessionID, using: runtime)
            if let id = subagentSessionID, fetchedSubagentID == nil {
                fetchedSubagentID = id
            }
        }
    }

    @ViewBuilder
    private var taskToolCard: some View {
        let status = toolStatus
        let subagentType = stringValue(for: "subagent_type") ?? "general"
        let promptText = stringValue(for: "description") ?? stringValue(for: "prompt") ?? toolCall.detail

        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon(status))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor(status))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(statusColor(status).opacity(0.18))
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(subagentType)
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textPrimary)
                        .lineLimit(1)

                    Text(statusLabel(status))
                        .font(.neoMonoSmall)
                        .foregroundStyle(statusColor(status))
                }

                if let promptText, !promptText.isEmpty {
                    Text(promptText)
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.textMuted)
                        .lineLimit(2)
                }

                if let outputText = outputExcerpt {
                    Text(outputText)
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.textSecondary)
                        .lineLimit(3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(NeoCodeTheme.panelSoft)
                        )
                }

                if let subagentID = subagentSessionID {
                    HStack(spacing: 16) {
                        Spacer()
                        Button(localized("View", locale: locale)) {
                            if let parentID = store.selectedSessionID {
                                store.navigateToSubagent(sessionID: subagentID, parentSessionID: parentID)
                            } else {
                                store.selectSession(subagentID)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(NeoCodeTheme.accentDim.opacity(0.22))
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func subagentCard(_ subagent: SessionSummary) -> some View {
        let status = status(for: subagent)

        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon(status))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor(status))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(statusColor(status).opacity(0.18))
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(subagent.title)
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textPrimary)
                        .lineLimit(1)

                    Text(statusLabel(status))
                        .font(.neoMonoSmall)
                        .foregroundStyle(statusColor(status))
                }

                if let excerpt = lastMessageExcerpt(for: subagent) {
                    Text(excerpt)
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.textMuted)
                        .lineLimit(2)
                }

                HStack(spacing: 16) {
                    Text(elapsedSince(subagent.lastUpdatedAt))
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.textMuted)

                    Spacer()

                    Button(localized("View", locale: locale)) {
                        store.selectSession(subagent.id)
                    }
                    .buttonStyle(.plain)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(NeoCodeTheme.accentDim.opacity(0.22))
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }

    private var toolStatus: SubagentStatus {
        if toolCall.status == .completed { return .completed }
        if toolCall.status == .error { return .error }
        return .running
    }

    private var outputExcerpt: String? {
        guard let raw = toolCall.output?.displayString else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyTrimmed
        guard let cleaned else { return nil }
        let maxLength = 200
        return cleaned.count > maxLength ? String(cleaned.prefix(maxLength)) + "..." : cleaned
    }

    private var subagentSessionID: String? {
        // Return fetched ID first (from runtime sync)
        if let fetched = fetchedSubagentID { return fetched }

        // First try: parse from output (available when task completes)
        if let raw = toolCall.output?.displayString {
            let pattern = /<task id="(ses_[a-zA-Z0-9]+)"/
            if let match = raw.firstMatch(of: pattern) {
                return String(match.1)
            }
        }
        // Second try: parse from detail (sometimes the ID appears here)
        let pattern = /<task id="(ses_[a-zA-Z0-9]+)"/
        if let match = toolCall.detail?.firstMatch(of: pattern) {
            return String(match.1)
        }
        return nil
    }

    private func stringValue(for key: String) -> String? {
        guard case .object(let dict) = toolCall.input,
              case .string(let value) = dict[key]
        else { return nil }
        return value
    }

    private enum SubagentStatus {
        case running, completed, error
    }

    private func status(for session: SessionSummary) -> SubagentStatus {
        if session.transcript.isEmpty {
            // No transcript loaded yet — fall back to runtime status
            switch session.status {
            case .running, .retrying, .awaitingInput:
                return .running
            case .error:
                return .error
            case .idle:
                return .completed
            }
        }

        let hasInProgress = session.transcript.contains(where: \.isInProgress)
        let hasToolError = session.transcript.contains { message in
            if case .toolCall(let toolCall) = message.kind,
               toolCall.status == .error {
                return true
            }
            return false
        }

        if hasToolError { return .error }
        if hasInProgress { return .running }
        return .completed
    }

    private func statusIcon(_ status: SubagentStatus) -> String {
        switch status {
        case .running: return "gearshape.2"
        case .completed: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    private func statusColor(_ status: SubagentStatus) -> Color {
        switch status {
        case .running: return NeoCodeTheme.accent
        case .completed: return NeoCodeTheme.success
        case .error: return NeoCodeTheme.warning
        }
    }

    private func statusLabel(_ status: SubagentStatus) -> String {
        switch status {
        case .running: return localized("Running", locale: locale)
        case .completed: return localized("Completed", locale: locale)
        case .error: return localized("Error", locale: locale)
        }
    }

    private func lastMessageExcerpt(for session: SessionSummary) -> String? {
        let lastText = session.transcript
            .filter { $0.role == .assistant }
            .last?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyTrimmed

        guard let lastText else { return nil }
        let maxLength = 120
        if lastText.count > maxLength {
            return String(lastText.prefix(maxLength)) + "..."
        }
        return lastText
    }

    private func elapsedSince(_ date: Date) -> String {
        let interval = abs(date.timeIntervalSinceNow)
        // Clamp insane values (uninitialized / distantPast)
        guard interval < 86400 * 365 else { return localized("Just now", locale: locale) }
        switch interval {
        case 0..<60: return localized("Just now", locale: locale)
        case 60..<120: return localized("1m ago", locale: locale)
        case 120..<3600: return "\(Int(interval / 60))m ago"
        case 3600..<7200: return localized("1h ago", locale: locale)
        default: return "\(Int(interval / 3600))h ago"
        }
    }
}
