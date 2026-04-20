# OpenBoringBar Agent Knowledge Base

This folder is the internal knowledge base for AI and human contributors.
It complements the root `AGENTS.md` entry doc with focused rules, workflows, templates, and checklists.

## Layout

```text
.agents/
  AGENTS.md
  skills/
    build-and-validate.md
    feature-delivery.md
    manual-regression.md
  rules/
    architecture-boundaries.md
    coding-conventions.md
    safety-red-lines.md
  mappings/
    module-ownership.yaml
    validation-scenarios.yaml
  docs/
    ai/
      workflow-overview.md
      troubleshooting.md
      event-bus-guidelines.md
  checklists/
    change-done-checklist.md
  templates/
    feature-spec-template.md
    pr-summary-template.md
  examples/
    change-note-example.md
```

## Usage Order

1. Read root `AGENTS.md` first.
2. Read `rules/` before writing code.
3. Follow `skills/feature-delivery.md` for implementation flow.
4. Run `skills/build-and-validate.md` for command-level validation.
5. Use `checklists/change-done-checklist.md` before opening a PR.

## Scope

- Product goal: stable BoringBar-like bottom taskbar behavior for multi-display macOS users.
- Technical baseline: macOS 14+, Swift 5, SwiftUI + AppKit + ApplicationServices.
- Build system: CocoaPods manages project/workspace generation.

Keep these docs updated whenever architecture, workflow, or contributor rules change.
