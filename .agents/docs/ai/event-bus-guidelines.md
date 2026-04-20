# Event Bus Guidelines

Use `OpenBoringBar/Core/Application/AppEventBus.swift` as the default cross-module event channel.

## Principles

1. Add typed `AppEvent` cases for new feature events.
2. Keep event payloads explicit and minimal.
3. Avoid string keys and `userInfo` dictionaries for app-internal contracts.

## When To Add A New Event

- A change in `Core/Bar` needs to update display UI state.
- Runtime coordinator needs to trigger behavior across managers.
- Cross-layer state transitions must be observed consistently.

## Event Design Tips

- Prefer domain model payloads instead of loosely typed tuples.
- Name events by intent, not by implementation details.
- Keep event handling on predictable actor/thread context.
