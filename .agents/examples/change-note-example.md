# Example Change Note

## Change

Implemented a safer per-display refresh path by separating app-order recomputation from display panel rendering updates.

## Layering

- Policy update in `Core/Bar`.
- Presentation update in `Core/DisplayBar`.
- No AX parsing logic introduced into display layer.

## Validation

- `./scripts/bootstrap.sh` passed.
- Manual checks passed for:
  - permission setup
  - multi-display bar lifecycle
  - capsule app switch
  - launcher search/launch
  - bottom guard behavior

## Docs

No architecture/workflow rule change in this example; AGENTS/README unchanged.
