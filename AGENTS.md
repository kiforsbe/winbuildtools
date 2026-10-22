# Instructions for coding agents

These rules apply to any coding agent working in this repository. Follow
[CONTRIBUTING.md](CONTRIBUTING.md) and [DEVELOPERS.md](DEVELOPERS.md) as well.

## Keep the documentation current

Update affected documentation in the same commit (or the same push, for a series)
as changes to behavior, public commands, configuration, security or contributor
processes. Check facts against the code and state what was and was not verified.

Update [ARCHITECTURE.md](ARCHITECTURE.md) when module responsibilities, helper
dependencies, data flow, public boundaries, failure handling or verification
coverage change. Keep script help and maintenance comments accurate in the same
change: explain purpose, inputs/results, side effects, non-obvious ordering,
identity/security constraints and resource cleanup rather than restating syntax.

## GitHub Actions

Keep workflows manual-only (`workflow_dispatch`). Do not dispatch a workflow as
part of publishing, tagging, pushing or routine verification unless the user
explicitly asks to run GitHub Actions. Run local verification instead; hosted
verification is a separate, explicitly requested action.

### Changelog entries

[CHANGELOG.md](CHANGELOG.md) follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), matching the
conventions used by VidVNC and our other projects.

- Add entries under `## [Unreleased]` at the top, creating that heading if it is
  missing. Never add new entries under a released version.
- Use these subsections, in this order, and only the ones needed: `### Added`,
  `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, `### Security`,
  then `### Known limitations`.
- Write for people using the tools and maintaining consuming projects: say what
  changed and what they will notice or need to do. Name commands, parameters,
  configuration fields and result fields exactly as they appear.
- Record implemented features, fixes, behavior changes, removals, security fixes
  and known limitations. Leave out plans, internal refactors, test-only and
  documentation-only changes unless they change what someone does.
- Keep entries brief: one or two lines saying what changed. Put explanations,
  implementation details and validation records in the appropriate guide and
  link to it from the entry.
- Use one entry per change; extend an existing `Unreleased` entry instead of
  adding a second one for the same feature.
- When preparing an owner-requested release, move the accumulated entries into
  `## [x.y.z] - YYYY-MM-DD`, using the actual version and release date. Keep
  newest releases first and open a new `Unreleased` section for subsequent work.
  Do not invent a release date or treat the initial local baseline as published.

## Dependency review

When selecting, adding, upgrading or reviewing dependencies, check the live
authoritative registry and upstream guidance for the latest listed stable
compatible versions, deprecations or replacement packages, known vulnerabilities,
and actual license and redistribution terms. Include transitive dependencies.
Do not assume an old pin, lock file, successful restore or familiar package name
means a dependency is current or safe. Prefer a coherent stable set; explain
compatibility exceptions and validate changes with the relevant builds and tests.
Never silently retain deprecated, vulnerable or prerelease packages, or claim
complete security based only on an advisory scan.
