# Skill: Build And Validate

Use this workflow after any code change.

## Quick Path

```bash
./scripts/bootstrap.sh
```

This script will:

1. Run `pod install`.
2. Build `OpenBoringBar` in Debug for macOS via `xcodebuild`.

## Manual Commands

```bash
pod install
xcodebuild \
  -project OpenBoringBar.xcodeproj \
  -scheme OpenBoringBar \
  -configuration Debug \
  -sdk macosx \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  build
```

## Expected Outputs

- No pod install failure.
- No compile/link failure.
- App target `OpenBoringBar` builds successfully.

## If Build Fails

1. Confirm changed files match layer boundaries.
2. Check for missing imports or access control issues.
3. Verify new files are under source globs used by `scripts/generate_xcodeproj.rb`.
4. Re-run `./scripts/bootstrap.sh` after fixing.
