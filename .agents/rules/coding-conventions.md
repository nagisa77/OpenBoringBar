# Coding Conventions

## File And Type Placement

1. One primary type per file.
- File name must match the primary type name.

2. Shared models must live in `OpenBoringBar/Core/Domain/Models/`.
- Do not define shared model structs inside managers or views.

3. Platform extensions belong in dedicated infra extension files.
- Example: `OpenBoringBar/Core/Infrastructure/Screen/NSScreen+DisplayID.swift`.

## Naming

- Orchestration: `*Coordinator`
- Long-lived behavior: `*Manager`
- Low-level adapters/readers: `*Provider`, `*Inspector`, `*Client`

## Access Control

- Default to `private` or `fileprivate`.
- Expose only APIs needed across module boundaries.

## Concurrency And Lifecycle

- UI-facing orchestration should be `@MainActor`.
- Timers/work items/observers must be cleaned up in `deinit`.

## Eventing

- Add new app-internal events as typed `AppEvent` cases.
- Avoid stringly typed `userInfo` payload contracts.

## Constants

- Keep shared constants in dedicated constant files.
- Avoid duplicating hardcoded values across modules.
