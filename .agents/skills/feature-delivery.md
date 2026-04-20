# Skill: Feature Delivery

Use this flow for any non-trivial feature or refactor.

## Phase 1: Boundary Design

1. Identify target layer (`Application`, `Bar`, `DisplayBar`, `Domain`, `Infrastructure`).
2. Define/extend domain models first when behavior is cross-cutting.
3. Add typed `AppEvent` cases before wiring event-driven behavior.

## Phase 2: Implementation

1. Implement runnable behavior first.
2. Keep one responsibility per file/type.
3. Reuse infra helpers (for example `AXElementInspector`) instead of duplicating AX parsing.

## Phase 3: Integration

1. Wire modules in `AppRuntimeCoordinator` where orchestration is needed.
2. Keep UI rendering in `Core/DisplayBar` and policy in `Core/Bar`.

## Phase 4: Validation

1. Run `./scripts/bootstrap.sh`.
2. Execute manual regression scenarios from `manual-regression.md`.
3. Record regression notes in PR or handoff message.

## Phase 5: Documentation Sync

If architecture/structure/workflow changed:

1. Update root `AGENTS.md`.
2. Update `README.md`.
3. Update relevant docs under `.agents/`.
