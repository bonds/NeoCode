import SwiftUI

struct SubagentTaskCardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.locale) private var locale

    let sessionID: String

    private var subagentSessions: [SessionSummary] {
        guard let project = store.projects.first(where: { $0.sessions.contains(where: { $0.id == sessionID }) })
        else { return [] }
        return project.childSessions(for: sessionID)
    }

    var body: some View {
        let subagents = subagentSessions

        if subagents.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(subagents) { subagent in
                    subagentCard(subagent)
                }
            }
        }
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

    private enum SubagentStatus {
        case running, completed, error
    }

    private func status(for session: SessionSummary) -> SubagentStatus {
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
        switch interval {
        case 0..<60: return localized("Just now", locale: locale)
        case 60..<120: return localized("1m ago", locale: locale)
        case 120..<3600: return "\(Int(interval / 60))m ago"
        case 3600..<7200: return localized("1h ago", locale: locale)
        default: return "\(Int(interval / 3600))h ago"
        }
    }
}
