# NeoCode Subagent Session Tree

## Summary

When the opencode runtime spawns a subagent (via the `task` tool), the subagent
runs as a separate session with its own transcript. NeoCode currently shows all
sessions flat in the sidebar with no distinction between root sessions and
subagent sessions, and provides no way to see what a subagent is doing.

This design adds a session tree hierarchy to the sidebar, inline subagent status
cards in the parent session's transcript, and back-navigation from subagent
sessions to their parent.

## Architecture

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `ProjectSummary.rootSessions` / `childSessions(for:)` | `AppModels.swift` | Split sessions into root (no parentID) and children (grouped by parentID) |
| `ProjectTreeNode` (modified) | `SidebarViews.swift` | Render root sessions + indented child rows for subagents |
| `SubagentTaskCardView` | New: `AppShell/SubagentViews.swift` | Inline rich card showing subagent status, excerpt, elapsed time, "View" button |
| Tool call detection | `ToolCallPresentation.swift` | Detect `task` tool calls and flag for subagent card rendering |
| Back-to-parent button | `ConversationHeaderViews.swift` | When viewing a subagent session, show back button in header |

### Data Flow

```
SSE event stream
  ↓
AppStore.apply(event:) processes message.updated / message.part.updated
  ↓
Parent session transcript updated with tool call for "task" tool
  ↓
Transcript rendering detects tool == "task" 
  ↓ (via ToolCallPresentation or ChatMessage.ToolCall.name)
SubagentTaskCardView rendered in place of (or alongside) tool call output
  ↓
Card reads subagent sessions from store (same project, parentID == currentSessionID)
  ↓
Card updates reactively as subagent events arrive (same SSE stream)
  ↓
User taps "View" → store.selectSession(subagent.id)
  ↓
ConversationHeader shows back button when selectedSession.parentID != nil
```

### Live Updates

No new event subscriptions needed. The existing `AppStore.apply(event:)` already
processes `message.updated` and `message.part.updated` for ALL sessions in the
project — including subagent sessions. The subagent's session data (transcript,
status, stats) is already being updated in the `ProjectSummary.sessions[]` array.

The `SubagentTaskCardView` reads from `@Environment(AppStore.self)` and
re-renders when the observed store publishes changes. This provides live status
updates (thinking → running → completed → error) without any additional
polling or SSE subscriptions.

### Status Granularity

The subagent card shows one of three statuses:
- **running** — session activity is `busy`, `retry`, or message is `inProgress`
- **completed** — the subagent's tool call has `status == .completed` and no `inProgress` messages
- **error** — the subagent's tool call has `status == .error`

These are already tracked by `ChatMessage.ToolCallStatus` and
`OpenCodePart.isInProgress`.

## Detailed Changes

### 1. Session Tree in Sidebar (`AppModels.swift` + `SidebarViews.swift`)

**`AppModels.swift` — `ProjectSummary`:**
- Add computed property: sessions with `parentID == nil` are root sessions
- Add method `childSessions(for parentID: String)`: returns sessions whose
  `parentID` matches the given ID
- `displayedSessions` should filter to root sessions only (matching opencode
  GUI behavior: `!session.parentID`)

**`SidebarViews.swift` — `ProjectTreeNode`:**
- After rendering each root session row, check if there are child subagent
  sessions via `project.childSessions(for: rootSession.id)`
- Render child rows with `.padding(.leading, 28)` (indent) using existing
  `SessionTreeRow` component
- The `isSelected` highlight works automatically — it compares session IDs

**Visual structure:**
```
Project A
├── Write tests for auth   ← root session
│   ├── Search fixtures    ← subagent, running  
│   └── Generate mocks     ← subagent, completed
├── Fix CSS bug            ← root session
```

### 2. Inline Subagent Card (`SubagentViews.swift`)

New file containing `SubagentTaskCardView`:

```swift
struct SubagentTaskCardView: View {
    let toolCall: ChatMessage.ToolCall
    @Environment(AppStore.self) private var store
    @Environment(\.locale) private var locale

    var body: some View {
        // Finds subagent sessions in the current project where
        // session.parentID == currentSessionID
        // Shows:
        // - Subagent title
        // - Status badge (running / completed / error)
        // - Last message excerpt (~120 chars)
        // - Elapsed time since created
        // - "View" button → store.selectSession(subagent.id)
    }
}
```

Detection in the transcript rendering:
- When rendering a tool call (`toolCall` in `ChatMessage`), check if
  `toolCall.name` normalized leaf name is `"task"`
- If yes, render `SubagentTaskCardView` instead of (or in addition to) the
  standard `ToolCallItemCardView`
- The card handles the "View" action by calling `store.selectSession(id:)`

### 3. Back Navigation (`ConversationHeaderViews.swift`)

When `selectedSession.parentID != nil`:
- Show a leading-chevron button to the left of the session title
- Button calls `store.selectSession(parentSessionID)`
- Label shows truncated parent session title
- Sidebar click also works: clicking the parent row calls
  `store.selectSession(parentID)` — this already functions once the sidebar
  tree renders parent sessions

Auto-expand the parent project in the sidebar:
- In `selectSession`, if the selected session has a `parentID`, expand the
  containing project (set `isCollapsed = false` for that project)

### 4. Tool Call Detection (`ToolCallPresentation.swift`)

The `ChatMessage.ToolCall.name` field stores the tool name as received from
the opencode runtime. The `task` tool sends `name = "task"`. Normalize it
using the existing `normalizedToolLeafName` pattern (lowercase, strip path
segments).

In `ToolCallPresentationBuilder.makeItems(for:)`, check if the tool name
is `"task"`. If so, return a minimal item or a special marker that the
transcript rendering can detect and render as `SubagentTaskCardView`.

## Files Touched

| File | Change |
|------|--------|
| `Models/AppModels.swift` | Add root/child session grouping methods |
| `AppShell/SidebarViews.swift` | Indent child rows under parent in `ProjectTreeNode` |
| `AppShell/SubagentViews.swift` (new) | `SubagentTaskCardView` |
| `AppShell/ConversationHeaderViews.swift` | Back-to-parent button |
| `Models/ToolCallPresentation.swift` | Detect `task` tool for subagent card |
| `AppShell/TranscriptViews.swift` | Wire subagent card into tool call rendering |

## Open Questions / Future Work

- **Subagent nesting deeper than one level** — currently sessions have a single
  `parentID`, but subagents can spawn their own subagents (depth up to 5 in
  the opencode runtime). The sidebar tree could support arbitrary depth by
  walking the `parentID` chain. Skip for initial implementation; depth-1 is
  sufficient for the common case.
- **Subagent session cleanup** — when the parent is deleted, should child
  sessions be deleted too? The opencode runtime may cascade deletes. Observe
  behavior and handle if needed.
- **Max visible children** — if a session spawns many subagents (e.g., 20),
  the sidebar could be cluttered. Start with all visible; add a "show more"
  toggle if it becomes a problem.
