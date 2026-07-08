# NeoCode Subagent Session Tree — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a session tree hierarchy to NeoCode's sidebar, inline subagent status cards, and back-navigation from subagent sessions.

**Architecture:** Group sessions by `parentID` in `ProjectSummary`, render indented child rows in `ProjectTreeNode`, detect `task` tool calls and render a `SubagentTaskCardView`, add a "back to parent" button in the conversation header.

**Tech Stack:** SwiftUI, Swift, macOS 15.4+

## Global Constraints

- Deployment target: macOS 15.4
- All new views must follow existing NeoCodeTheme styling (reuse `Font.neo*`, `NeoCodeTheme.*` color tokens)
- Use `@Environment(AppStore.self)` for store access in views
- Use `@Environment(\.locale)` and `localized()` for user-facing strings
- Follow the existing file organization (models in `Models/`, views in `AppShell/`)

---

### Task 1: Add root/child session grouping to ProjectSummary

**Files:**
- Modify: `Models/AppModels.swift`

**Interfaces:**
- Produces: `ProjectSummary.rootSessions: [SessionSummary]` — sessions where `parentID == nil`
- Produces: `ProjectSummary.rootAndChildSessions: [(root: SessionSummary, children: [SessionSummary])]` — paired list for sidebar rendering
- Produces: `ProjectSummary.childSessions(for parentID: String) -> [SessionSummary]` — sessions matching that parentID

- [ ] **Step 1: Add root session grouping to ProjectSummary**

Add computed properties to `ProjectSummary` in `AppModels.swift`:

```swift
extension ProjectSummary {
    var rootSessions: [SessionSummary] {
        sessions.filter { $0.parentID == nil }
    }

    func childSessions(for parentID: String) -> [SessionSummary] {
        sessions.filter { $0.parentID == parentID }
    }

    typealias SessionGroup = (root: SessionSummary, children: [SessionSummary])

    var rootAndChildSessions: [SessionGroup] {
        rootSessions.map { root in
            (root: root, children: childSessions(for: root.id))
        }
    }
}
```

Place this at the end of `AppModels.swift` (before the last newline, after the `RevertPreviewFileChange` struct or wherever the last struct ends — around line 742).

- [ ] **Step 2: Verify the build**

```bash
cd /Users/scott/src/bonds/neocode && XCS_HIDE_SCM=YES xcodebuild build -project "NeoCode.xcodeproj" -scheme "NeoCode" -configuration Debug -derivedDataPath /tmp/neocode-build-plan CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Models/AppModels.swift
git commit -m "feat: add root/child session grouping to ProjectSummary"
```

---

### Task 2: Render indented child sessions in sidebar

**Files:**
- Modify: `AppShell/SidebarViews.swift`

**Interfaces:**
- Consumes: `ProjectSummary.rootAndChildSessions`, `ProjectSummary.rootSessions`, `ProjectSummary.childSessions(for:)` (from Task 1)
- Produces: Updated `ProjectTreeNode` that renders root sessions with indented children

- [ ] **Step 1: Read the current sidebar session rendering**

The current code in `ProjectTreeNode` (around line 257):
```swift
ForEach(project.displayedSessions(showAll: showsAllSessions)) { session in
    SessionTreeRow(session: session, isSelected: store.selectedSessionID == session.id)
        .onTapGesture {
            store.selectSession(session.id)
        }
}
```

Replace with nested `ForEach` using the new grouping:

```swift
// Replace from line 251 (the `if !store.isProjectCollapsed...` block start) onward
if !store.isProjectCollapsed(project.id) {
    VStack(alignment: .leading, spacing: 2) {
        if shouldShowSessionSyncIndicator {
            ProjectSessionSyncRow()
        }

        ForEach(project.rootSessions) { rootSession in
            let isRootSelected = store.selectedSessionID == rootSession.id
            let children = project.childSessions(for: rootSession.id)
            let isAnyChildSelected = children.contains(where: { $0.id == store.selectedSessionID })

            SessionTreeRow(session: rootSession, isSelected: isRootSelected || isAnyChildSelected)
                .onTapGesture {
                    store.selectSession(rootSession.id)
                }

            if !children.isEmpty {
                ForEach(children) { child in
                    SessionTreeRow(session: child, isSelected: store.selectedSessionID == child.id)
                        .padding(.leading, 28)
                        .onTapGesture {
                            store.selectSession(child.id)
                        }
                }
            }
        }

        if project.hasHiddenSessions {
            Button(action: toggleSessionExpansion) {
                Text(sessionExpansionLabel)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.accent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
    }
    .padding(.leading, 14)
}
```

But also change the `displayedSessions(showAll:)` — it's currently used for root session display. Since we now use `rootSessions`, we should modify `displayedSessions` to only return root sessions:

In `AppModels.swift`, modify the existing `displayedSessions` method:

```swift
func displayedSessions(showAll: Bool = false) -> [SessionSummary] {
    let ordered = rootSessions // was: sessions
        .enumerated()
        .sorted { lhs, rhs in
            if lhs.element.sidebarOrderingDate != rhs.element.sidebarOrderingDate {
                return lhs.element.sidebarOrderingDate > rhs.element.sidebarOrderingDate
            }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
    guard !showAll else { return ordered }
    return Array(ordered.prefix(Self.displayedSessionLimit))
}
```

However, `hasHiddenSessions` and `hiddenSessionCount` should also account for root sessions, not total sessions. Update them:

```swift
var hiddenSessionCount: Int {
    max(0, rootSessions.count - Self.displayedSessionLimit)
}

var hasHiddenSessions: Bool {
    hiddenSessionCount > 0
}
```

- [ ] **Step 2: Build and verify**

```bash
cd /Users/scott/src/bonds/neocode && XCS_HIDE_SCM=YES xcodebuild build -project "NeoCode.xcodeproj" -scheme "NeoCode" -configuration Debug -derivedDataPath /tmp/neocode-build-plan CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Models/AppModels.swift AppShell/SidebarViews.swift
git commit -m "feat: render indented child sessions in sidebar tree"
```

---

### Task 3: Detect task tool call and wire SubagentTaskCardView into transcript

**Files:**
- Modify: `Models/ToolCallPresentation.swift`
- Modify: `AppShell/TranscriptViews.swift`

**Interfaces:**
- Consumes: `ProjectSummary.childSessions(for:)` (from Task 1), `selectSession(_:)` on store
- Produces: Subagent card shown in parent session transcript when a `task` tool call is present

- [ ] **Step 1: Add task tool detection to ToolCallPresentation**

In `ToolCallPresentationBuilder.makeItems(for:)`, check if the tool name is `"task"`. The `ChatMessage.ToolCall.name` field contains the tool name. The existing code normalizes tool names via `normalizedToolLeafName` (lowercased, path-separator stripped).

Add a static helper to detect task tools:

```swift
// Add to ToolCallPresentation or ToolCallPresentationBuilder
static func isTaskTool(_ toolCall: ChatMessage.ToolCall) -> Bool {
    toolCall.name.lowercased().split(whereSeparator: { $0 == "." || $0 == ":" || $0 == "/" }).last.map(String.init) == "task"
}
```

Place this at the end of `ToolCallPresentation.swift` (inside `ToolCallPresentationBuilder`).

- [ ] **Step 2: Wire subagent card detection in transcript rendering**

In `TranscriptViews.swift`, find where tool call items are rendered. Look for the `ToolCallItemCardView` usage:

```swift
ToolCallItemCardView(item: item, toolStatus: toolCall.status, contentWidth: contentWidth)
```

(This is around line 326 — search for `ToolCallItemCardView`.)

Before this line, check if the tool call is a task tool. If so, render a `SubagentTaskCardView` instead. Since `SubagentTaskCardView` isn't written yet (Task 4), for now add a placeholder condition:

Find the code that renders tool items (look for `ForEach` over `presentation.items`). It should be inside `ToolCallClusterRowView` or `ToolCallRowView`. The tool call's `name` is available from `ChatMessage.ToolCall`.

For now, add a comment/placeholder:

```swift
// In the area where ToolCallItemCardView is rendered (around line 326-340):
// TODO: If toolCall is a task tool, render SubagentTaskCardView instead
// This will be wired in Task 4
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/scott/src/bonds/neocode && XCS_HIDE_SCM=YES xcodebuild build -project "NeoCode.xcodeproj" -scheme "NeoCode" -configuration Debug -derivedDataPath /tmp/neocode-build-plan CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Models/ToolCallPresentation.swift AppShell/TranscriptViews.swift
git commit -m "feat: add task tool detection for subagent card rendering"
```

---

### Task 4: Create SubagentTaskCardView

**Files:**
- Create: `AppShell/SubagentViews.swift`

**Interfaces:**
- Consumes: `AppStore` (via `@Environment`), `ProjectSummary.childSessions(for:)`, `selectSession(_:)`
- Produces: Rich card view rendered inline in the parent session transcript

- [ ] **Step 1: Create the SubagentTaskCardView**

Create `AppShell/SubagentViews.swift`:

```swift
import SwiftUI

struct SubagentTaskCardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.locale) private var locale

    let sessionID: String

    private var subagentSessions: [SessionSummary] {
        guard let session = store.sessionSummary(for: sessionID),
              let projectID = store.projectID(for: sessionID),
              let project = store.projects.first(where: { $0.id == projectID })
        else { return [] }

        return project.sessions.filter { $0.parentID == sessionID }
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
            // Status icon
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

                // Last message excerpt
                if let excerpt = lastMessageExcerpt(for: subagent) {
                    Text(excerpt)
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.textMuted)
                        .lineLimit(2)
                }

                HStack(spacing: 16) {
                    // Elapsed time
                    Text(elapsedSince(subagent.lastUpdatedAt))
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.textMuted)

                    Spacer()

                    // View button
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
        // Check if the session has any in-progress tool calls or unfinished messages
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
```

- [ ] **Step 2: Wire SubagentTaskCardView into transcript rendering**

In `TranscriptViews.swift`, find the `ToolCallItemCardView` rendering. Replace the placeholder from Task 3 with actual rendering:

```swift
// Around line 326, inside the tool call items rendering:
if ToolCallPresentation.isTaskTool(toolCall) {
    SubagentTaskCardView(sessionID: sessionID)
} else {
    ToolCallItemCardView(item: item, toolStatus: toolCall.status, contentWidth: contentWidth)
}
```

To find the exact location: search for `ToolCallItemCardView` in `TranscriptViews.swift`. It should be inside a `ForEach` that iterates `presentation.items`. The parent context has access to `toolCall` and `sessionID`.

The `sessionID` is available nearby — look for where `ToolCallRowView` or `ToolCallItemCardView` is called (it should have a `message` or `sessionID` context).

- [ ] **Step 3: Build and verify**

```bash
cd /Users/scott/src/bonds/neocode && XCS_HIDE_SCM=YES xcodebuild build -project "NeoCode.xcodeproj" -scheme "NeoCode" -configuration Debug -derivedDataPath /tmp/neocode-build-plan CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add AppShell/SubagentViews.swift AppShell/TranscriptViews.swift
git commit -m "feat: add SubagentTaskCardView with status, excerpt, and View button"
```

---

### Task 5: Add back-to-parent navigation button

**Files:**
- Modify: `AppShell/ConversationHeaderViews.swift`

**Interfaces:**
- Consumes: `selectedSession.parentID`, `store.selectSession(_:)`
- Produces: Back button in the header when viewing a subagent session

- [ ] **Step 1: Read the current ConversationHeaderView**

Read the session header view in `ConversationHeaderViews.swift`. The session's `parentID` is accessible via `store.sessionSummary(for: sessionID)?.parentID`.

Find the header's title area (around line 105-120 in ConversationHeaderViews.swift) where the session title is displayed.

- [ ] **Step 2: Add back button**

In the header, before the session title, add:

```swift
if let parentID = parentSessionID,
   let parentTitle = parentSessionTitle {
    Button(action: { store.selectSession(parentID) }) {
        HStack(spacing: 4) {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))

            Text(parentTitle)
                .font(.neoMonoSmall)
                .lineLimit(1)
        }
        .foregroundStyle(NeoCodeTheme.accent)
    }
    .buttonStyle(.plain)
    .help(localized("Back to parent session", locale: locale))
}
```

Add computed properties to the view:

```swift
private var parentSessionID: String? {
    guard let sessionID else { return nil }
    return store.sessionSummary(for: sessionID)?.parentID
}

private var parentSessionTitle: String? {
    guard let parentID else { return nil }
    return store.sessionSummary(for: parentID)?.title
}
```

Add `@State private var sessionID: String` — or extract it from the existing environment. The session header already has access to the current session. Look for existing `sessionID` or `store.selectedSessionID` usage in the header.

The exact placement: after the `WindowDragRegion` and before the workspace tools / git actions. The header is an HStack with the title and actions. Add the back button as a leading HStack element when a parent exists.

- [ ] **Step 3: Auto-expand project when navigating to subagent**

In `AppStore.swift`, modify `selectSession` to auto-expand the parent project when a subagent is selected. Add after setting `selectedSessionID`:

```swift
// In selectSession(_:), after setting selectedSessionID and selectedProjectID:
if let parentID = session(for: sessionID)?.parentID,
   sessionID != parentID,
   let projectID = selectedProjectID {
    expandProjectIfCollapsed(projectID)
}
```

But actually, this is already handled by the `selectSession` function's effect on the sidebar. The sidebar checks `store.isProjectCollapsed(project.id)` and only displays sessions when not collapsed. To auto-expand, add:

```swift
// In AppStore.swift, find the selectSession method (around line 782)
// After `selectedSessionID = sessionID` and `selectedProjectID = destinationProjectID`:
if session(for: sessionID)?.parentID != nil, let projectID = destinationProjectID {
    collapsedProjectIDs.remove(projectID)
}
```

Check if `collapseProjectIDs` is a Set or similar. Search for `isProjectCollapsed` in `AppStore.swift` to find the implementation:

```swift
// Example based on toggle implementation:
func isProjectCollapsed(_ projectID: ProjectSummary.ID) -> Bool {
    collapsedProjectIDs.contains(projectID)
}
```

Add the auto-expand logic after the existing `selectSession` body's state assignments (after line 793 or wherever the initial state is set).

- [ ] **Step 4: Build and verify**

```bash
cd /Users/scott/src/bonds/neocode && XCS_HIDE_SCM=YES xcodebuild build -project "NeoCode.xcodeproj" -scheme "NeoCode" -configuration Debug -derivedDataPath /tmp/neocode-build-plan CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add AppShell/ConversationHeaderViews.swift AppStore.swift
git commit -m "feat: add back-to-parent navigation in conversation header"
```

---

### Task 6: Final integration and release

- [ ] **Step 1: Full build with Release config**

```bash
rm -rf /tmp/neocode-build && cd /Users/scott/src/bonds/neocode && XCS_HIDE_SCM=YES xcodebuild build -project "NeoCode.xcodeproj" -scheme "NeoCode" -configuration Release -derivedDataPath /tmp/neocode-build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Verify parentID propagation**

Check that `SessionSummary` correctly preserves `parentID` from the opencode session. The `init(session:fallbackTitle:composerState:)` initializer at `AppModels.swift:108-119` maps `session.parentID` to `self.parentID`. This should already work — verify it's present:

```swift
// At AppModels.swift line 115:
parentID: session.parentID,
```

- [ ] **Step 3: Create versioned release**

```bash
cd /Users/scott/src/bonds/neocode && VERSION="0.8.2-$(date -u +%Y%m%d%H%M)-$(git rev-parse --short=7 HEAD)" && TAG="v${VERSION}" && rm -f NeoCode.dmg && hdiutil create -volname NeoCode -srcfolder /tmp/neocode-build/Build/Products/Release/NeoCode.app -ov -format UDZO NeoCode.dmg 2>&1 | grep "created" && NOTES_FILE=$(mktemp) && PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null) && git log "${PREV_TAG}..HEAD" --oneline --no-decorate > "$NOTES_FILE" && gh release create "$TAG" NeoCode.dmg --repo bonds/NeoCode --title "NeoCode $VERSION" --notes-file "$NOTES_FILE" && rm "$NOTES_FILE"
```

Also bump the MARKETING_VERSION in `project.pbxproj` from `0.8.1` to `0.8.2` for this release:

```bash
sed -i '' 's/MARKETING_VERSION = 0.8.1;/MARKETING_VERSION = 0.8.2;/g' NeoCode.xcodeproj/project.pbxproj
```

- [ ] **Step 4: Update flake + deploy**

```bash
HASH=$(nix-prefetch-url --type sha256 "https://github.com/bonds/NeoCode/releases/download/${TAG}/NeoCode.dmg") && SRI=$(nix hash to-sri --type sha256 "$HASH") && sed -i '' -e "s/version = \".*\";/version = \"${VERSION}\";/" -e "s|hash = \"sha256-.*\";|hash = \"${SRI}\";|" flake.nix && git add flake.nix && git commit -m "release: $VERSION" && git push "https://bonds:$(gh auth token)@github.com/bonds/NeoCode.git" main 2>&1
```

- [ ] **Step 5: Tell user to run nr**
