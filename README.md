# Coppermind

A note-taking app for macOS and iOS that auto-categorizes, connects, clusters, and prioritizes your thoughts. Built with SwiftUI and SwiftData.

> **For agents:** If you make changes to this repo, update this README to reflect them. Keep the architecture diagram, file index, and build instructions accurate. Don't let this doc drift from the code.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    App Targets                       │
│  CoppermindMac (@main)    CoppermindIOS (@main)     │
│  3-column split view      Priority feed + tabs       │
└──────────────────────┬──────────────────────────────┘
                       │ depends on
┌──────────────────────▼──────────────────────────────┐
│                  CoppermindCore                       │
│                                                      │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ NoteStore│──│   Engines    │  │    Models      │  │
│  │ (facade) │  │              │  │                │  │
│  └──────────┘  │ Categorize   │  │ Note (@Model)  │  │
│                │ Connect      │  │ Connection     │  │
│                │ Cluster      │  │ AudioRecording │  │
│                │ Rank         │  │ NoteGroup      │  │
│                │ AudioPipeline│  │                │  │
│                └──────────────┘  └───────────────┘  │
│                                                      │
│  ViewModels: NoteEditor, NoteList, Dashboard,        │
│              AudioCapture                            │
│  Subdirectories: Categorization/, Connections/,      │
│                  Audio/                              │
└──────────────────────────────────────────────────────┘
```

## Targets

| Target | Type | Platform | Entry Point |
|--------|------|----------|-------------|
| `CoppermindCore` | Library | macOS 15+ / iOS 18+ | — |
| `CoppermindMac` | Executable | macOS 15+ | `CoppermindMacApp.swift` |
| `CoppermindIOS` | Executable | iOS 18+ | `CoppermindIOSApp.swift` |
| `CoppermindTests` | Test | macOS | — |

No external dependencies. Pure Swift using SwiftUI, SwiftData, Speech, and AVFoundation.

## Data Models

All models use `@Model` (SwiftData). Schema lives in `CoppermindCore/Sources/Models/`.

### Note

The core entity. Supports four categories: **idea**, **task**, **project**, **bucket**.

| Property | Type | Purpose |
|----------|------|---------|
| `title` | String | Display name |
| `body` | String | Content (aliased as `text`) |
| `category` | NoteCategory | Auto-assigned or manual |
| `priorityScore` | Double | Composite score (aliased as `priority`) |
| `dueDate` | Date? | Task deadline (aliased as `deadline`) |
| `source` | NoteSource | `.typed` or `.audio` |
| `isArchived`, `isPinned`, `isStarred` | Bool | State flags |
| `connectionIDs` | [UUID] | Engine compatibility |
| `clusterName` | String? | Assigned cluster |

Relationships: `outgoingConnections`, `incomingConnections`, `audioRecordings`, `groups`.

Engine compatibility aliases (`text`, `priority`, `deadline`) exist so the root-level engines can reference notes without knowing the canonical property names.

### Connection

Directed edge between two notes with a strength score (0.0–1.0) and relationship type (related, follow-up, contradicts, supports, reference).

### AudioRecording

Metadata for a voice memo: file path, duration, transcription text, confidence score. The `note` relationship is optional (recording can be created before the note exists).

### NoteGroup

Cluster container with a name, member notes, and optional embedding centroid (serialized `[Float]`).

## Engines

All engines are structs in `CoppermindCore/Sources/`. `NoteStore` is the facade that composes them.

| Engine | What it does |
|--------|-------------|
| **CategorizationEngine** | Rule-based text classification → category + base priority. Detects task verbs, deadline signals, project keywords, idea markers. |
| **ConnectionEngine** | Keyword overlap analysis. Extracts significant words (≥3 chars, minus stopwords), pairs notes with ≥2 shared keywords. |
| **ClusterEngine** | BFS over keyword-affinity graph → connected components. Names clusters from top-5 frequent keywords. |
| **PriorityRanker** | Composite scoring: base priority + overdue bonus (+40) + connection bonus (+5/link) + category bonus + recency decay. |
| **AudioPipeline** | Record → transcribe (Apple Speech) → categorize → produce (Note, AudioRecording). Uses `AudioRecorderProtocol` and `AudioTranscriber` protocols. |

## Views

### macOS (CoppermindMac)

Three-column `NavigationSplitView`:

| View | Column | Purpose |
|------|--------|---------|
| `SidebarView` | Leading | Smart groups (Today, High Priority, Recent), category filters, system sections (All, Pinned, Archived). Badge counts. |
| `NoteListView` | Content | Filtered/sorted note rows. Search bar. Swipe actions (pin, archive, delete). Sort picker (priority, recency, alpha). |
| `NoteDetailView` | Detail | Title/body editor, category picker, audio recordings list, connections panel toggle, metadata footer. |
| `ConnectionsPanelView` | Sheet/overlay | View/add/remove connections grouped by type. |
| `QuickCaptureView` | — | Quick note entry. |

### iOS (CoppermindIOS)

| View | Purpose |
|------|---------|
| `HomeView` | Priority-ranked feed with Urgent/Important/Browse sections. Empty state with brain icon. |
| `CategoryTabView` | Tab-based category browser. |
| `IOSNoteDetailView` | Note editor for iOS. |
| `AudioCaptureOverlayView` | Recording UI with waveform and transcription. |

## Building

### macOS

```bash
cd /path/to/Coppermind
swift build --target CoppermindCore --target CoppermindMac
swift run CoppermindMac
```

### iOS (requires Xcode + Simulator)

```bash
SIMULATOR_ID=$(xcrun simctl list devices available | grep "iPhone" | head -1 | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot $SIMULATOR_ID
open -a Simulator

xcodebuild -scheme CoppermindIOS \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  build

# SPM produces a bare binary — wrap it in a .app bundle:
DERIVED=$(find ~/Library/Developer/Xcode/DerivedData/Coppermind-*/Build/Products/Debug-iphonesimulator -maxdepth 0)
mkdir -p "$DERIVED/CoppermindIOS.app"
cp "$DERIVED/CoppermindIOS" "$DERIVED/CoppermindIOS.app/CoppermindIOS"
# (see validation/validating-macos-ios-apps/launching-apps.md for full Info.plist)

xcrun simctl install $SIMULATOR_ID "$DERIVED/CoppermindIOS.app"
xcrun simctl launch $SIMULATOR_ID com.coppermind.ios
```

### Tests

```bash
swift build --target CoppermindTests
swift test --skip-build
```

Note: `swift test` builds all targets including the iOS one, which fails on macOS. Build the test target explicitly first, then run with `--skip-build`.

## File Index

```
Coppermind/
├── Package.swift
├── CoppermindCore/Sources/
│   ├── Models/
│   │   ├── Note.swift              # @Model + enums + Notification.Name.newNote
│   │   ├── Connection.swift        # @Model
│   │   ├── AudioRecording.swift    # @Model
│   │   └── NoteGroup.swift         # @Model
│   ├── NoteStore.swift             # Facade: addNote, rankedNotes, clusters
│   ├── CategorizationEngine.swift  # Rule-based classifier
│   ├── ConnectionEngine.swift      # Keyword overlap linker
│   ├── ClusterEngine.swift         # BFS clustering
│   ├── PriorityRanker.swift        # Composite scoring
│   ├── AudioPipeline.swift         # Record → transcribe → categorize
│   ├── Categorization/
│   │   ├── CategoryClassifier.swift
│   │   └── RuleBasedClassifier.swift
│   ├── Connections/
│   │   ├── ConnectionDiscovery.swift
│   │   └── NoteClusterer.swift
│   ├── Audio/
│   │   ├── AudioRecorder.swift     # AVAudioEngine implementation
│   │   └── TranscriptionService.swift # Apple Speech framework
│   └── ViewModels/
│       ├── NoteEditorViewModel.swift
│       ├── NoteListViewModel.swift
│       ├── DashboardViewModel.swift
│       ├── AudioCaptureViewModel.swift
│       └── SyncManager.swift
├── CoppermindMac/Sources/
│   ├── CoppermindMacApp.swift      # @main, 3-column layout
│   └── Views/
│       ├── SidebarView.swift
│       ├── NoteListView.swift
│       ├── NoteDetailView.swift
│       ├── ConnectionsPanelView.swift
│       └── QuickCaptureView.swift
├── CoppermindIOS/Sources/
│   ├── CoppermindIOSApp.swift      # @main, HomeView
│   └── Views/
│       ├── HomeView.swift
│       ├── CategoryTabView.swift
│       ├── IOSNoteDetailView.swift
│       └── AudioCaptureOverlayView.swift
├── CoppermindTests/Sources/
│   ├── CoppermindIntegrationTests.swift
│   ├── AudioPipelineTests.swift
│   ├── ConnectionTests.swift
│   ├── IntegrationTests.swift
│   └── ModelTests.swift
└── validation/
    └── validating-macos-ios-apps/  # QA skill (SKILL.md + reference files)
```

## Known Issues

- **Audio capture has no macOS UI trigger.** The backend (AudioRecorder, TranscriptionService, AudioPipeline) is fully implemented. The iOS `AudioCaptureOverlayView` exists. But neither app has a button wired to start recording.
- **iOS has no create-note button.** The empty state says "Tap + to capture your first thought" but no + button exists.
- **`swift test` builds all targets.** The iOS target fails to compile on macOS because of iOS-only APIs (`topBarTrailing`, `navigationBarTitleDisplayMode`). Use `swift build --target CoppermindTests && swift test --skip-build`.
- **CategorizationEngine task-verb priority.** "Buy groceries" gets classified as `.task` (matches "buy" verb) instead of `.bucket`. Task verbs are checked before bucket keywords.

## Origin

This codebase was generated by a multi-model Attractor pipeline (see the parent repo `jc_attractor`). Two independent models produced the SwiftData models and the root-level engines respectively, which originally had incompatible property names. Compatibility aliases on `Note` (`text`↔`body`, `priority`↔`priorityScore`, `deadline`↔`dueDate`) bridge the two layers so both compile without modifying the engines.

## Updating This README

If you are an agent working on this repo:

1. **After adding/removing files:** Update the File Index section.
2. **After changing models:** Update the Data Models section (properties, relationships).
3. **After changing engines:** Update the Engines table.
4. **After adding/removing views:** Update the Views section.
5. **After fixing known issues:** Remove them from Known Issues.
6. **After changing build steps:** Update the Building section.
7. **After adding new known issues:** Add them to Known Issues.

Keep this README as the single source of truth for anyone (human or agent) picking up this project.
