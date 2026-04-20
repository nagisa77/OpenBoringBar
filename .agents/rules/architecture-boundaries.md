# Architecture Boundaries

## Layer Direction

Allowed dependency direction:

`App -> Core/Application -> (Core/Bar + Core/DisplayBar) -> (Core/Domain + Core/Infrastructure)`

## Responsibilities

1. `OpenBoringBar/App`
- App entry and top-level flow only.
- Do not place AX/CGWindow policy logic here.

2. `OpenBoringBar/Core/Application`
- Runtime orchestration and module wiring.
- Use typed events via `AppEventBus`.

3. `OpenBoringBar/Core/Bar`
- Core behavior: app discovery, switching, ordering, bottom guard policy.

4. `OpenBoringBar/Core/DisplayBar`
- Display panel lifecycle and SwiftUI/AppKit rendering.
- Must not own AX/CGWindow policy.

5. `OpenBoringBar/Core/Domain/Models`
- Shared value types and entities.
- Keep dependency-light: prefer Foundation/CoreGraphics only.

6. `OpenBoringBar/Core/Infrastructure`
- System adapters and low-level inspectors/providers.
- No product-level orchestration.

## Hard Rules

- `Domain` must not depend on Application/Bar/DisplayBar/UI.
- `Infrastructure` must not depend on UI modules.
- Cross-module events must be typed (`AppEvent`), not raw `Notification.Name` payloads.
- Shared constants go into dedicated constant files (for example `BarLayoutConstants`).
