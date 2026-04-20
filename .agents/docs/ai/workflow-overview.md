# OpenBoringBar AI Workflow Overview

This document explains how an agent should execute changes safely.

## End-To-End Flow

```text
Request Intake
  -> Boundary Selection (module/layer)
  -> Model/Event Design (if cross-cutting)
  -> Code Change (small, layered)
  -> Build Validation (bootstrap)
  -> Manual Regression (5 core scenarios)
  -> Documentation Sync (AGENTS + README when needed)
  -> Handoff with verification notes
```

## Decision Guardrails

- Prefer behavior correctness and stability over visual polish.
- Prefer typed events over ad-hoc notifications.
- Keep policies in `Core/Bar`; keep view lifecycle/rendering in `Core/DisplayBar`.

## Definition Of Done

A change is done when all are true:

1. Build passes using `./scripts/bootstrap.sh`.
2. Relevant manual regression scenarios are verified.
3. Docs are updated when architecture/workflow changed.
4. No layer boundary violation introduced.
