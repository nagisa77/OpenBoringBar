# OpenBoringBar

OpenBoringBar is an open-source alternative to [boringbar.app](https://boringbar.app), focused on delivering a practical macOS bottom taskbar experience for multi-display setups.

## Core Goals

- One bottom bar per display.
- Clear running/visible app representation.
- Fast app switching from the bar.
- Stability and maintainability before visual complexity.

## Requirements

- macOS 14+
- Xcode 26+
- CocoaPods (`pod` available in shell)

## Bootstrap And Build

```bash
./scripts/bootstrap.sh
```

This script runs:

1. `pod install` to regenerate project/workspace metadata.
2. `xcodebuild` for a Debug build of scheme `OpenBoringBar`.

## Manual Commands

```bash
pod install
xcodebuild -project OpenBoringBar.xcodeproj -scheme OpenBoringBar -configuration Debug -sdk macosx -destination 'platform=macOS' build
```

## Architecture Snapshot

```text
OpenBoringBar/
├── App
│   ├── OpenBoringBarApp.swift
│   ├── PermissionManager.swift
│   └── PermissionSetupView.swift
├── Core
│   ├── Application
│   │   ├── AppEventBus.swift
│   │   └── AppRuntimeCoordinator.swift
│   ├── Bar
│   │   ├── ActiveWindowBottomGuardManager.swift
│   │   ├── BarLayoutConstants.swift
│   │   └── BarManager.swift
│   ├── DisplayBar
│   │   ├── DisplayBottomBarView.swift
│   │   └── DisplayPanelController.swift
│   ├── Domain
│   │   └── Models
│   │       └── BarModels.swift
│   └── Infrastructure
│       ├── Accessibility
│       │   └── AXElementInspector.swift
│       └── Screen
│           └── NSScreen+DisplayID.swift
└── Resources
```

## Collaboration Rules

- Do not edit `OpenBoringBar.xcodeproj` directly.
- If project-generation behavior must change, update `scripts/generate_xcodeproj.rb`.
- Follow coding/layering rules in [AGENTS.md](./AGENTS.md), including model placement and dependency direction.

## Documentation Freshness

When code changes, docs must stay in sync:

- Update `README.md` for user-visible behavior or architecture snapshot changes.
- Update `AGENTS.md` for contributor/agent coding workflow or convention changes.
- For architectural refactors, update both files in the same PR.

## License

OpenBoringBar is released under the MIT License. See [LICENSE](./LICENSE) for details.
