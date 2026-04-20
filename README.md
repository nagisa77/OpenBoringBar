# OpenBoringBar

<p align="center">
  <img src="docs/assets/app-icon.png" alt="OpenBoringBar App Icon" width="160" />
</p>

OpenBoringBar is an open-source alternative to [boringbar.app](https://boringbar.app), focused on delivering a practical macOS bottom taskbar experience for multi-display setups.

## Screenshots

### Normal Bar

![Normal Bar](docs/screenshots/normal-looks-like.png)

### Multi-Window Preview

![Multi-Window Preview](docs/screenshots/multi-preview-window.png)

### App Launcher Search

![App Launcher Search](docs/screenshots/file-search.png)


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

## Agent Workspace

This repository includes an AI contributor knowledge base under `.agents/`.

- Entry point: `AGENTS.md`
- Knowledge base index: `.agents/AGENTS.md`
- Rules: `.agents/rules/`
- Workflows: `.agents/skills/`
- Validation checklist: `.agents/checklists/change-done-checklist.md`

Recommended reading order for contributors and coding agents:

1. `AGENTS.md`
2. `.agents/rules/`
3. `.agents/skills/feature-delivery.md`
4. `.agents/skills/build-and-validate.md`
5. `.agents/skills/manual-regression.md`

## License

OpenBoringBar is released under the MIT License. See [LICENSE](./LICENSE) for details.
