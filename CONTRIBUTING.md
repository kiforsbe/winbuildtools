# Contributing

Keep reusable mechanisms here and application policy in consuming repositories.
Open an issue with a reproducible synthetic payload/configuration before proposing
a new installer behavior. Do not include real secrets, signing keys or user data.

For changes, add meaningful regression coverage and run ./verify.ps1 -Integration
on a compatible Windows host, plus git diff --check. Record exact commands,
platform/SDK versions and untested behavior. Test from a consumer pinned checkout
when changing public paths, commands, result fields or source layout. Inspect
both MSI architectures when changing authoring or identity rules.

Dependencies require current upstream/registry version, deprecation, advisory,
license and transitive review; a successful restore or scanner result alone is
not sufficient. Prefer the existing dependency-free implementation. Never hide
an exception or add a build-time fetch of the latest tool revision.

Preserve MIT copyright/license text and provenance. Contributions are submitted
under this repository's MIT License. Changes must be reviewed before release;
manual-only CI needs to be run deliberately. Follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
and report suspected vulnerabilities through [SECURITY.md](SECURITY.md).
