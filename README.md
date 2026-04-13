# OpenBoringBar

OpenBoringBar is an open-source alternative to [boringbar.app](https://boringbar.app), focused on bringing a practical macOS bottom taskbar experience to multi-display setups.

## Project Focus

- Build a real, usable bottom bar for each connected display on macOS.
- Show running/open apps clearly in each bar.
- Support fast app switching by clicking an app item.
- Keep implementation pragmatic and maintainable over visual complexity.

## Why This Project

This repository exists to provide a transparent, community-driven implementation of the BoringBar-style workflow. The goal is to make the core experience accessible, hackable, and extensible in the open.

## License

OpenBoringBar is released under the MIT License.

- You are free to use, modify, and distribute this project.
- Contributions are accepted under the same MIT terms.

See [LICENSE](./LICENSE) for details.

## Requirements

- macOS 14+
- Xcode 26+
- CocoaPods (`pod` available in shell)

## Bootstrap And Build

```bash
./scripts/bootstrap.sh
```

This script runs:

1. `pod install` to generate and maintain the Xcode project/workspace.
2. `xcodebuild` for a Debug build using the `OpenBoringBar` scheme.

## Manual Commands

```bash
pod install
xcodebuild -project OpenBoringBar.xcodeproj -scheme OpenBoringBar -configuration Debug -sdk macosx -destination 'platform=macOS' build
```

## Repository Layout

```text
.
├── AGENTS.md
├── Podfile
├── OpenBoringBar
│   ├── App
│   ├── Core
│   └── Resources
└── scripts
    ├── bootstrap.sh
    └── generate_xcodeproj.rb
```

## Contributing

Issues and pull requests are welcome.
Before making changes, read [AGENTS.md](./AGENTS.md) for collaboration and build rules.
