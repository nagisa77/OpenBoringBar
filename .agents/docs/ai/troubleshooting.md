# Troubleshooting

## pod install fails

- Confirm CocoaPods is installed and available in shell.
- Re-run from repo root.
- Check network and local Ruby/CocoaPods environment.

## xcodebuild fails after adding files

- Ensure new files are under:
  - `OpenBoringBar/App/**/*.swift`
  - `OpenBoringBar/Core/**/*.swift`
- If project reference drift is suspected:
  - run `pod install`
  - if still needed, regenerate with `ruby scripts/generate_xcodeproj.rb` then `pod install`

## Layer violation during refactor

- Move shared value types into `Core/Domain/Models`.
- Move AX or system parsing into `Core/Infrastructure`.
- Keep display policy out of `Core/DisplayBar`.

## Runtime regressions but build is green

- Re-run the manual regression skill checklist.
- Validate with multi-display hardware scenario, not single display only.
