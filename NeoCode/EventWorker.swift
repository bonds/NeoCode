import Foundation
import OSLog

// MARK: - Shared types

/// Key for buffered text deltas, used by both EventWorker and AppStore.
struct BufferedTextDeltaKey: Hashable {
    let projectID: ProjectSummary.ID
    let sessionID: String
    let partID: String
}

struct BufferedTextDelta: Sendable {
    let messageID: String
    var text: String
    var updatedAt: Date
}

// MARK: - Mutations

/// Lightweight, Sendable descriptions of state changes to apply on the main actor.
enum StateMutation: Sendable {
    /// Set the live status for a session
    case setLiveStatus(sessionID: String, status: OpenCodeSessionActivity, isBusy: Bool)
    /// Pre-computed session status from transcript traversal
    case setResolvedStatus(sessionID: String, projectID: ProjectSummary.ID, status: SessionStatus)
    /// A message part delta to buffer for later flush
    case bufferDelta(key: BufferedTextDeltaKey, delta: String, messageID: String)
    /// Pre-assembled transcript update (text already concatenated)
    case updateTranscript(sessionID: String, messages: [ChatMessage])
    /// Insert child session silently
    case insertChildSession(projectID: ProjectSummary.ID, session: SessionSummary)
    /// Upsert a root session (via normal upsert path)
    case upsertRootSession(projectID: ProjectSummary.ID, session: SessionSummary, isCreated: Bool)
    /// Remove a session
    case removeSession(sessionID: String, projectID: ProjectSummary.ID)
    /// Mark session as locally deleted
    case markLocallyDeleted(sessionID: String, projectID: ProjectSummary.ID)
    /// Compact a session
    case compactSession(sessionID: String, projectID: ProjectSummary.ID)
    /// Update info for a message
    case updateMessageInfo(sessionID: String, info: OpenCodeMessageInfo)
    /// Update message roles
    case updateMessageRoles(roles: [(String, ChatMessage.Role)])
}

/// Background actor that processes SSE events and produces StateMutations.
/// The actor does the heavy computation (string manipulation, array traversal)
/// and the main actor applies the cheap result.
actor EventWorker {
    private let logger = Logger(subsystem: "tech.watzon.NeoCode", category: "EventWorker")

    /// Process a single event, producing zero or more StateMutations.
    /// `transcript` is a COPY of the current transcript — the worker can traverse it
    /// without blocking the main thread.
    func process(
        _ event: OpenCodeEvent,
        projectID: ProjectSummary.ID,
        transcript: [ChatMessage],
        sessionIDs: Set<String>,
        hasBufferedDeltas: Bool
    ) -> [StateMutation] {
        var mutations: [StateMutation] = []

        switch event {
        case .sessionStatusChanged(let sessionID, let status):
            mutations.append(.setLiveStatus(sessionID: sessionID, status: status, isBusy: status == .busy))
            // Compute resolved status from the cloned transcript
            let resolved = computeResolvedStatus(transcript: transcript, sessionID: sessionID)
            if let resolved {
                mutations.append(.setResolvedStatus(sessionID: sessionID, projectID: projectID, status: resolved))
            }

        case .sessionCreated(let session), .sessionUpdated(let session):
            let summary = SessionSummary(session: session)
            if session.isRootVisible {
                let fallbackTitle = SessionSummary.defaultTitle
                var s = summary
                s = SessionSummary(session: session, fallbackTitle: fallbackTitle)
                mutations.append(.upsertRootSession(projectID: projectID, session: s, isCreated: event.isCreated))
            } else if session.parentID != nil, !sessionIDs.contains(session.id) {
                mutations.append(.insertChildSession(projectID: projectID, session: summary))
            } else if session.parentID == nil {
                mutations.append(.markLocallyDeleted(sessionID: session.id, projectID: projectID))
            }

        case .sessionDeleted(let sessionID):
            mutations.append(.markLocallyDeleted(sessionID: sessionID, projectID: projectID))

        case .sessionCompacted(let sessionID):
            mutations.append(.compactSession(sessionID: sessionID, projectID: projectID))

        case .messageUpdated(let info):
            mutations.append(.updateMessageRoles(roles: [(info.id, info.chatRole)]))
            if let sessionID = info.sessionID {
                mutations.append(.updateMessageInfo(sessionID: sessionID, info: info))
            }

        case .messagePartUpdated(let part):
            if let sessionID = part.sessionID {
                if let message = ChatMessage(part: part) {
                    mutations.append(.updateTranscript(sessionID: sessionID, messages: [message]))
                }
            }

        case .messagePartDelta(let delta):
            let key = BufferedTextDeltaKey(
                projectID: projectID,
                sessionID: delta.sessionID,
                partID: delta.partID
            )
            mutations.append(.bufferDelta(key: key, delta: delta.delta, messageID: delta.messageID))

        default:
            break
        }

        return mutations
    }

    /// Compute session status by traversing the transcript.
    /// This runs on the background actor using the cloned transcript.
    private func computeResolvedStatus(transcript: [ChatMessage], sessionID: String) -> SessionStatus? {
        let hasInProgress = transcript.contains(where: \.isInProgress)
        if hasInProgress { return .running }

        if let last = transcript.last {
            if case .toolCall = last.kind {
                return .running
            }
        }

        return .idle
    }
}
