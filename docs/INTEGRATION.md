# Consuming a pinned checkout

The expected layout inside an application repository is:

```text
external/winbuildtools/       # Git submodule pinned by the application commit
deployment/msi.json          # Application-owned product configuration
deployment/AppxManifest.xml  # Application-owned MSIX manifest, if used
scripts/package.ps1          # Application adapter: publish, approve, package, sign
```

## Add after publication

Replace placeholders with the actual hosting URL and a reviewed full commit.
These commands are a deliberate integration/update operation, never a build step.

```powershell
git submodule add https://github.com/OWNER/winbuildtools.git external/winbuildtools
git -C external/winbuildtools checkout --detach REVIEWED_FULL_COMMIT
git add .gitmodules external/winbuildtools
git commit -m "Pin Windows build tools"
```

The .gitmodules entry records the URL; the gitlink records the exact tool commit.
Do not commit a local filesystem URL or a sibling developer checkout as the
consumer's shared URL. Publish the referenced commit before publishing a consumer
change that depends on it. A tag can help select a release, but the gitlink is
the actual immutable commit selection.

## Clone and build

```powershell
git clone --recurse-submodules https://github.com/OWNER/APPLICATION.git
# For an existing checkout, including after switching application branches:
git submodule update --init --recursive
```

Use the paths under the application's external/winbuildtools checkout. Never
search sibling folders, fall back to a vendored copy, or download latest tooling
when the checkout is missing. The example [adapter](../examples/consumer-package.ps1)
can be copied to the consumer root. If moved into scripts/, adjust its consumer
root explicitly; product JSON remains in the application repository.

The generic MSI config is JSON schemaVersion 1. MSIX uses the normal app manifest
XML rather than duplicating capabilities and extensions in JSON. Tool version,
config schema version and application package version are independent values.
Consumers retain required-file checks, privilege policy, dependency/license
review and final package/signature acceptance.

## GitHub consumer checkout

For consumers already using actions/checkout, configure their independently
reviewed, full-SHA-pinned action with:

```yaml
with:
  submodules: recursive
  persist-credentials: false
```

For native Git checkout, run git submodule update --init --recursive after
checking out the application commit. Fetching the parent alone does not populate
the submodule. This repository's own CI has no external submodule dependency.

For private tooling repositories, the application's ordinary GITHUB_TOKEN may
not grant cross-repository read access. Provision a narrowly scoped GitHub App
installation token or other approved read credential and make it available only
during checkout/submodule initialization. Do not put tokens in .gitmodules,
remote URLs, product JSON or logs; do not persist credential configuration.
See GitHub's [token guidance](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token).

## Upgrade deliberately

```powershell
git -C external/winbuildtools fetch origin
git -C external/winbuildtools checkout --detach NEW_REVIEWED_FULL_COMMIT
# Run application builds, package inspection and the relevant acceptance checks.
git add external/winbuildtools
git commit -m "Update pinned Windows build tools"
```

Do not use submodule update --remote in ordinary builds. An application branch
must continue to build with its recorded tool commit after new tool releases.
Older commits must remain reachable on the hosting repository.

The checkout model follows [Git's submodule documentation](https://git-scm.com/docs/gitsubmodules).
Agenda and ProcSight have not been migrated by this setup.
