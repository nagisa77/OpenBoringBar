# OpenBoringBar Agent Guide

## Mission

OpenBoringBar is an open-source implementation inspired by [boringbar.app](https://boringbar.app).
Our priority is to deliver a reliable bottom taskbar experience for macOS multi-display users in a fully transparent codebase.

## Product Direction

1. Keep focus on the core BoringBar-like workflow: per-display bars, running app visibility, and app switching.
2. Optimize for real usability and stability before visual polish.
3. Build in public so contributors can inspect, extend, and improve behavior.

## Technical Baseline

1. Platform: `macOS 14+`
2. Language: `Swift 5`
3. UI stack: `SwiftUI` + `AppKit` + `ApplicationServices`
4. Project generation: `CocoaPods` (`pod install` regenerates and maintains Xcode project)

## Current Architecture (Post-Refactor)

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
```

## Layer Responsibilities (Must Follow)

1. `App/`
   - App entry and top-level screen flow only.
   - No heavy AX/CGWindow business logic.
2. `Core/Application/`
   - Runtime orchestration and module wiring.
   - Coordinates feature managers through typed interfaces/events.
3. `Core/Bar/`
   - Core business behavior for app discovery, app activation, window guard logic.
4. `Core/DisplayBar/`
   - Display panel/window lifecycle and bar rendering.
5. `Core/Domain/Models/`
   - Shared domain entities and value objects.
   - Must be dependency-light (prefer `Foundation` / `CoreGraphics` only).
6. `Core/Infrastructure/`
   - System API adapters/wrappers (`AX`, `NSScreen`, `CGWindowList`, etc.).
   - Reusable low-level helpers, no product-level orchestration.

## Dependency Direction (Must Follow)

1. Allowed direction: `App -> Application -> (Bar/DisplayBar) -> Domain + Infrastructure`.
2. `Domain` must not depend on `Application`, `Bar`, `DisplayBar`, or UI code.
3. `Infrastructure` must not depend on UI layer.
4. `DisplayBar` must not contain AX/CGWindow business policy.
5. Cross-module communication must prefer typed events (`AppEventBus`) over stringly-typed notifications.

## Coding & Placement Conventions (Strict)

1. **Model placement (mandatory)**
   - Shared entities/objects/value types must live in `Core/Domain/Models/`.
   - Do not define shared model structs inside managers/views.
2. One primary type per file.
   - File name must match primary type name.
3. Extensions placement.
   - Put platform extensions in dedicated files under `Core/Infrastructure/...`.
   - Example: `NSScreen+DisplayID.swift`.
4. Manager/Coordinator naming.
   - Orchestration types: `*Coordinator`.
   - Long-lived behavior types: `*Manager`.
   - Low-level readers/helpers: `*Inspector` / `*Client` / `*Provider`.
5. Access control.
   - Default to `private`/`fileprivate` for internals.
   - Expose only what other modules need.
6. Concurrency.
   - UI-facing orchestration types should be `@MainActor`.
   - Timer/work item lifecycle must be explicitly cancelled in `deinit`.
7. Eventing.
   - New feature events must be added as typed `AppEvent` cases.
   - Avoid raw `Notification.Name` + `userInfo` for app-internal events.
8. Reuse infra helpers.
   - AX attribute/window parsing must go through shared infra helpers (for example `AXElementInspector`) unless there is a strong reason not to.
9. Constants.
   - Shared constants belong in dedicated constants files (for example `BarLayoutConstants`).
   - Avoid hardcoded values scattered across multiple modules.

## Feature Development Rules

1. Implement runnable behavior first, then polish visuals.
2. Keep each PR small and layered; avoid mixing architecture rewrite and unrelated UI polish.
3. For new cross-cutting behavior, define boundaries first (models/events/interfaces), then implement.
4. Do not directly edit `OpenBoringBar.xcodeproj`.
   - If source-reference behavior needs change, update `scripts/generate_xcodeproj.rb`.

## Validation Rules (Per Change)

After every code change:

1. Run `./scripts/bootstrap.sh` and resolve build issues.
2. Provide regression validation notes (at least manual verification steps).
3. Verify at least relevant scenarios:
   - Permission setup flow.
   - Multi-display bar create/remove.
   - App switch from capsule.
   - Application launcher open/search/launch.
   - Bottom guard behavior for frontmost window.

## Documentation Freshness Policy (Strict)

1. Any architecture/structure/workflow convention update must update both:
   - `AGENTS.md`
   - `README.md`
2. Any user-visible behavior change must reflect in `README.md`.
3. Any coding-rule/process change for contributors/agents must reflect in `AGENTS.md`.
4. Do not leave docs stale after refactors. Documentation sync is part of Definition of Done.

## License Policy

1. This project follows the MIT License.
2. New code and documentation contributions must be MIT-compatible.
3. If adding third-party code/dependencies, verify license compatibility before merging.
