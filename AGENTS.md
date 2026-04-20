# OpenBoringBar Agent Guide

> AI collaboration entry for OpenBoringBar.
> Goal: deliver a stable bottom taskbar experience for multi-display macOS users in a transparent and contributor-friendly codebase.

## Mission

OpenBoringBar is an open-source implementation inspired by [boringbar.app](https://boringbar.app).
Priority is reliability of core behavior before visual polish.

## Product Direction

1. Keep focus on BoringBar-like core workflow:
   - per-display bars
   - running app visibility
   - app switching
2. Optimize for real usability and stability first.
3. Build in public so contributors can inspect and extend behavior.

## Technical Baseline

1. Platform: `macOS 14+`
2. Language: `Swift 5`
3. UI stack: `SwiftUI` + `AppKit` + `ApplicationServices`
4. Project generation: `CocoaPods` (`pod install` maintains project/workspace)

## Repository Structure

```text
.
├── OpenBoringBar/
│   ├── App/
│   ├── Core/
│   │   ├── Application/
│   │   ├── Bar/
│   │   ├── DisplayBar/
│   │   ├── Domain/Models/
│   │   └── Infrastructure/
│   └── Resources/
├── scripts/
│   ├── bootstrap.sh
│   └── generate_xcodeproj.rb
├── docs/
├── .agents/
│   ├── AGENTS.md
│   ├── skills/
│   ├── rules/
│   ├── mappings/
│   ├── docs/ai/
│   ├── checklists/
│   ├── templates/
│   └── examples/
└── AGENTS.md
```

## .agents Knowledge Base

Use `.agents/` as the practical operating handbook.

1. `rules/`: hard boundaries and coding constraints
2. `skills/`: executable workflows (delivery/build/regression)
3. `mappings/`: machine-readable ownership and validation mapping
4. `docs/ai/`: deeper technical notes and troubleshooting
5. `checklists/`: done criteria
6. `templates/`: feature spec and PR summary templates
7. `examples/`: concrete handoff examples

Recommended read order:

1. `AGENTS.md` (this file)
2. `.agents/rules/*.md`
3. `.agents/skills/feature-delivery.md`
4. `.agents/skills/build-and-validate.md`
5. `.agents/checklists/change-done-checklist.md`

## Core Commands

```bash
# Full bootstrap + build (required after every code change)
./scripts/bootstrap.sh

# Regenerate Xcode project from source globs (only when needed)
ruby scripts/generate_xcodeproj.rb
pod install

# Manual build command
xcodebuild \
  -project OpenBoringBar.xcodeproj \
  -scheme OpenBoringBar \
  -configuration Debug \
  -sdk macosx \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  build
```

## Current Architecture (Must Follow)

Current source layout:

```text
OpenBoringBar/
  App/
    OpenBoringBarApp.swift
    PermissionManager.swift
    PermissionSetupView.swift
  Core/
    Application/
      AppRuntimeCoordinator.swift
      AppEventBus.swift
    Bar/
      BarAccessibilityObserverManager.swift
      BarAppSnapshot.swift
      BarDisplayAppOrderManager.swift
      BarDisplayStateBuilder.swift
      BarManager.swift
      ActiveWindowBottomGuardManager.swift
      BarLayoutConstants.swift
    DisplayBar/
      AppWindowPreviewPanelView.swift
      AppWindowPreviewPanelWindow.swift
      ApplicationLauncherPopoverView.swift
      DisplayPanelController.swift
      DisplayBottomBarView.swift
    Domain/
      Models/
        AppWindowPreviewItem.swift
        BarModels.swift
        LaunchableApplicationItem.swift
    Infrastructure/
      Application/
        InstalledApplicationProvider.swift
        WindowPreviewProvider.swift
      Accessibility/
        AXElementInspector.swift
      Screen/
        NSScreen+DisplayID.swift
  Resources/
    Assets.xcassets/
      AppIcon.appiconset/
    Info.plist
```

## Layer Responsibilities

1. `App/`
   - App entry and top-level screen flow only.
   - No heavy AX/CGWindow business logic.
2. `Core/Application/`
   - Runtime orchestration and module wiring.
   - Coordinate feature managers through typed events/interfaces.
3. `Core/Bar/`
   - Core business behavior for app discovery, activation, ordering, window guard.
4. `Core/DisplayBar/`
   - Display panel/window lifecycle and bar rendering.
5. `Core/Domain/Models/`
   - Shared entities/value objects.
   - Keep dependency-light (`Foundation`/`CoreGraphics` preferred).
6. `Core/Infrastructure/`
   - System adapters/wrappers (`AX`, `NSScreen`, `CGWindowList`, etc.).
   - Reusable low-level helpers only.

## Dependency Direction

1. Allowed direction:
   `App -> Application -> (Bar/DisplayBar) -> Domain + Infrastructure`
2. `Domain` must not depend on `Application`, `Bar`, `DisplayBar`, or UI code.
3. `Infrastructure` must not depend on UI layer.
4. `DisplayBar` must not contain AX/CGWindow business policy.
5. Cross-module communication must prefer typed events (`AppEventBus`).

## Coding And Placement Conventions (Strict)

1. Shared models must live in `Core/Domain/Models/`.
2. One primary type per file; file name must match primary type.
3. Platform extensions in dedicated infra extension files.
4. Naming:
   - `*Coordinator`: orchestration
   - `*Manager`: long-lived behavior
   - `*Inspector` / `*Client` / `*Provider`: low-level helpers
5. Access control defaults to `private`/`fileprivate`.
6. UI-facing orchestration types should be `@MainActor`.
7. Timer/work item lifecycle must be explicitly cancelled in `deinit`.
8. New feature events must be typed `AppEvent` cases.
9. Reuse infrastructure helpers (for example `AXElementInspector`) when parsing AX/window attributes.
10. Shared constants belong in dedicated constant files.

## Standard Delivery Flow

```text
Phase 1: Boundary design
  pick layer + define events/models when cross-cutting

Phase 2: Implementation
  ship runnable behavior first, keep changes layered

Phase 3: Validation
  run ./scripts/bootstrap.sh
  run manual regression scenarios

Phase 4: Documentation sync
  update AGENTS.md + README.md when architecture/workflow conventions changed
```

Detailed playbooks:

- `.agents/skills/feature-delivery.md`
- `.agents/skills/build-and-validate.md`
- `.agents/skills/manual-regression.md`

## Validation Rules (Per Change)

After every code change:

1. Run `./scripts/bootstrap.sh` and resolve build issues.
2. Provide regression validation notes (at least manual verification steps).
3. Verify relevant scenarios:
   - permission setup flow
   - multi-display bar create/remove
   - app switch from capsule
   - launcher open/search/launch
   - bottom guard behavior for frontmost window

## Documentation Freshness Policy (Strict)

1. Any architecture/structure/workflow convention update must update both:
   - `AGENTS.md`
   - `README.md`
2. Any user-visible behavior change must reflect in `README.md`.
3. Any coding-rule/process change for contributors/agents must reflect in `AGENTS.md`.
4. Do not leave docs stale after refactors.

## Forbidden Actions

1. Do not manually edit `OpenBoringBar.xcodeproj`.
   - If source-reference behavior needs change, edit `scripts/generate_xcodeproj.rb`.
2. Do not skip build validation.
3. Do not mix broad architecture rewrites with unrelated UI polish in one change.

## License Policy

1. This project follows the MIT License.
2. New code and documentation contributions must be MIT-compatible.
3. If adding third-party code/dependencies, verify license compatibility before merge.
