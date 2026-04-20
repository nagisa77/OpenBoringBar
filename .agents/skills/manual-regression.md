# Skill: Manual Regression

Run these scenarios after successful build.

## 1) Permission Setup Flow

- Launch app with missing permissions.
- Verify onboarding/setup UI appears.
- Grant required permissions and confirm app transitions to running state.

## 2) Multi-Display Bar Create/Remove

- Attach two or more displays.
- Confirm each display has a bottom bar.
- Disconnect/reconnect displays and confirm bars are removed/recreated correctly.

## 3) App Switch From Capsule

- Open several apps.
- Click capsule items from the bar.
- Verify frontmost app switches correctly and consistently.

## 4) Application Launcher Open/Search/Launch

- Open launcher popover.
- Search by app name.
- Launch selected app and verify focus behavior.

## 5) Bottom Guard Behavior

- Bring frontmost windows to the lower screen edge.
- Verify guard behavior prevents unintended overlap/conflict with bar.

## Regression Notes Template

- Build command and result.
- Devices/displays used.
- Scenario-by-scenario pass/fail.
- Any flaky or uncertain behavior with reproduction steps.
