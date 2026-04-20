# Safety Red Lines

## Project File Generation

- Do not manually edit `OpenBoringBar.xcodeproj`.
- If source reference behavior must change, update `scripts/generate_xcodeproj.rb`.

## Validation Cannot Be Skipped

- Every code change must run `./scripts/bootstrap.sh`.
- Build must pass before handing off work.

## Scope Discipline

- Prefer small, layered PRs.
- Avoid mixing architecture rewrites with unrelated visual polish.

## Documentation Freshness

When architecture/structure/workflow conventions change, update both:

- `AGENTS.md`
- `README.md`

Do not leave docs stale after refactors.

## Licensing

- Project license is MIT.
- Added dependencies or copied code must be MIT-compatible.
