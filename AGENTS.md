# OpenBoringBar Agent Guide

## Mission

OpenBoringBar is an open-source implementation inspired by [boringbar.app](https://boringbar.app).  
Our priority is to deliver a reliable, bottom-taskbar experience for macOS multi-display users in a fully transparent codebase.

## Product Direction

1. Keep focus on the core BoringBar-like workflow: per-display bars, running app visibility, and app switching.
2. Optimize for real usability and stability before visual polish.
3. Build in public so contributors can inspect, extend, and improve behavior.

## Technical Baseline

1. Platform: `macOS 14+`
2. Language: `Swift 5`
3. UI stack: `SwiftUI` + `AppKit` (screen/window interaction)
4. Project generation: `CocoaPods` (`pod install` generates and maintains project files)

## Architecture Direction

1. `BarManager`: screen change observation, running app aggregation, switch-action routing.
2. `BarWindowController`: one bar window per `NSScreen`.
3. `AppSwitcher`: app activation and window-focus strategy.
4. `UI`: per-display rendering and interaction layer.

## Collaboration Rules

1. Prioritize runnable behavior first, then iterate on visuals.
2. Every feature change must include regression validation notes (at least manual verification steps).
3. After each change, run `./scripts/bootstrap.sh` and resolve compile issues.
4. Do not edit `OpenBoringBar.xcodeproj` directly.  
   If source references must change, update `scripts/generate_xcodeproj.rb` (auto-collects `OpenBoringBar/App/**/*.swift` and `OpenBoringBar/Core/**/*.swift`).
5. When product direction changes, update both this file and `README.md` in the same PR.

## License Policy

1. This project follows the MIT License.
2. New code and documentation contributions must be MIT-compatible.
3. If adding third-party code/dependencies, verify license compatibility before merging.
