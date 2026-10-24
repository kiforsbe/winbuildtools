# Consuming a pinned checkout

The expected layout inside an application repository is:

```text
external/winbuildtools/       # Git submodule pinned by the application commit
deployment/msi.json          # Application-owned product configuration
deployment/AppxManifest.xml  # Application-owned MSIX manifest, if used
scripts/package.ps1          # Application adapter: publish, approve, package, sign
scripts/setup-dev-certificate.ps1  # Optional explicit wrapper around shared command
scripts/trust-dev-certificate.ps1  # Optional explicit administrative wrapper
```

Use every applicable shared mechanism, not just MSI/MSIX creation. A complete
migration removes local copies of certificate validation, signing/verification,
development-key creation/trust, SDK discovery, process logging and artifact
hash/signature metadata. Consumers keep product data and policy and delegate
these mechanisms through the same pinned checkout.

## Add the published tools

Use the published URL and a reviewed release or full commit (for example v0.4.0).
These commands are a deliberate integration/update operation, never a build step.

```powershell
git submodule add https://github.com/kiforsbe/winbuildtools.git external/winbuildtools
git -C external/winbuildtools checkout --detach v0.4.0
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
when the checkout is missing. The [MSI-only adapter](../examples/consumer-package.ps1)
demonstrates locating the checkout and invoking one packer; it is not a complete
packaging migration. The complete ownership checklist and composition examples
below also apply. If an adapter lives in scripts/, derive the consumer root with
`Split-Path $PSScriptRoot -Parent`; the MSI-only example is copied to the root.

The generic MSI config supports JSON schemaVersion 1 and opt-in schemaVersion 2.
Use [the v2 contract](../msi/README.md#configuration-version-2) to supply resolved
GUIDs, exact install/menu names, scope choice and servicing policy. An adapter
that preserves an existing product must compute those compatibility inputs in
the consumer and emit a complete component map after preparing the payload.
Keep v1 for existing consumers until intentionally migrating. MSIX uses the normal app manifest
XML rather than duplicating capabilities and extensions in JSON. Tool version,
config schema version and application package version are independent values.
Consumers retain required-file checks, privilege policy, dependency/license
review and final package/signature acceptance.

Version 0.3.0 changes newly authored MSI maintenance to request normal Restart
Manager application shutdown, without automatic relaunch. Consumers must handle
Windows session-ending messages, including tray mode, and validate the installed
servicing lifecycle before shipping application installers. Older built/cached
MSIs keep their previous policy. See [UI policy and acceptance requirements](../msi/README.md#running-applications).

## What consumers keep and delegate

The native-wizard work is included in `v0.4.0`, promoted from `v0.4.0-beta.1`
without executable changes. Deliberately pin the reviewed release/commit and rebuild
consumer MSIs. Keep the entire `msi/` directory when copying;
`Registration.ps1` and `Wizard.ps1` are required helpers. Existing CLI/result names
and v1 identities are retained. Optional `ui.allowDirectoryChange`, `ui.licenseText`
and `application.appUserModelId` are described in [native setup](../msi/README.md#native-setup-and-maintenance).
Use the app's existing identity, not a new generic ID, and keep product/license
policy in the consumer. New packages remember same-context custom destinations;
older installed packages lack that record and require their known `INSTALLFOLDER`
on upgrade. Do not claim Start right-click Uninstall from metadata inspection:
complete [installed acceptance](MSI-ACCEPTANCE.md) with rebuilt consumer packages.

Beta `v0.5.0-beta.1` adds `ui` fields for both layouts, consumer logo/sidebar artwork,
native Browse and configurable finish messages/details/HTTPS links/launch. Use
[example-ui.json](../msi/example-ui.json) as a full v2 example; the same object
works with v1. The `v0.4.0` release does not include these newer fields. Deliberately
pin `v0.5.0-beta.1` to opt in. Image paths are relative to the
approved payload; include them in v2 component maps. Product URLs/artwork/messages
belong in the consumer configuration. Launch is disabled unless enabled there,
and still requires the user to check the final-page checkbox. Validate its Windows
identity and permissions before enabling it in a production consumer installer.

| Concern | Consumer keeps | Shared mechanism to invoke |
| --- | --- | --- |
| Product build | Project/SDK selection, runtime/architecture/configuration, restore audit policy and compatibility workarounds | `dotnet/invoke.ps1` where its context matches the project; otherwise use `Invoke-WbtTool` for product-specific build commands |
| Payload approval | Required files, WinUI resources, notification-runtime checks, assets, package/runtime license materials | Product validation before calling either packer; no generic tool can infer these requirements |
| MSI | Permanent upgradeCode, product/version/configuration and approved file list | `msi/package.ps1`, including its inspection gate |
| MSIX | Publisher, version, architecture, capabilities, extensions and generated manifest | `msix/package.ps1`; `msix/inspect.ps1` for separately produced packages |
| Signing preflight | Whether signing is requested, expected publisher, selected identity and timestamp/trust policy | `Assert-WbtSigningOptions`, `Get-WbtSigningCertificate`; dispose the returned certificate |
| Signing/verification | Explicit signer and choice of `RequireTrusted` | `signing/sign.ps1`, `signing/verify.ps1` (or corresponding functions in `Signing.ps1`) |
| Development key | Explicit subject, public CER destination and decision to create a new key | `signing/new-dev-certificate.ps1`, separately from packaging |
| Development trust | Reviewed thumbprint, deployment/removal policy and explicit administrative invocation | `signing/trust-dev-certificate.ps1`, separately from packaging |
| SDK/process utilities | Which tool is needed and where product logs belong | `Get-WbtSdkTool` and `Invoke-WbtTool` from `common/Tools.ps1` |
| Final metadata | Source revision/dirty state, product release fields and compatibility aliases | `common/write-artifact-manifest.ps1`, then additive composition described below |

For Agenda this means retaining `deployment/msi.json`, manifest generation,
publishing/resources/required-file checks and license/audit policy, while replacing
local generic `scripts/packaging/Signing.ps1` and SDK/logging/hash implementations.
Certificate setup/trust entry points may remain for command compatibility, but
must wrap the shared commands rather than reimplement certificate/store logic.
Preserve the application's existing public arguments and result fields in its
adapter. Remove copied helpers only after callers and tests use the shared ones.

## Package, sign and record final bytes

Resolve the checkout once from the consumer script, then use it for all operations.
For a script located in the consumer's scripts/ directory:

```powershell
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tools = Join-Path $root 'external/winbuildtools'
if (!(Test-Path -LiteralPath (Join-Path $tools 'VERSION') -PathType Leaf)) {
    throw 'winbuildtools checkout is missing. Run: git submodule update --init --recursive'
}
. (Join-Path $tools 'common/Tools.ps1')
. (Join-Path $tools 'signing/Signing.ps1')
```

The following fragments belong inside that adapter, after it has bound its product
parameters. `$payload`, `$buildRoot`, `$version`, `$Architecture`, `$Format` and
`$Publisher` are consumer-owned values. Use a fresh absolute `$buildRoot` outside
the payload. Do not enumerate or package its diagnostics as application content.

Preflight signing before an expensive build when any signing option is supplied.
Pass the expected MSIX publisher, or an empty string for MSI. The helper requires
exactly one explicit certificate selection, a private key, a valid time interval
and code-signing EKU. No certificate is selected or generated for unsigned builds.

```powershell
$signingOptions = @{
    CertificateThumbprint = $CertificateThumbprint
    CertificatePath = $CertificatePath
    CertificatePassword = $CertificatePassword
    TimestampUri = $TimestampUri
}
$sign = $false
if ($CertificateThumbprint -or $CertificatePath) { $sign = $true }
if ($sign -or $CertificatePassword -or $TimestampUri) {
    Assert-WbtSigningOptions @signingOptions
    $expectedPublisher = if ($Format -eq 'Msix') { $Publisher } else { '' }
    $certificate = Get-WbtSigningCertificate -CertificateThumbprint $CertificateThumbprint `
        -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword `
        -Publisher $expectedPublisher
    try { $null = Get-WbtSdkTool signtool.exe } finally { $certificate.Dispose() }
}
```

After the consumer publishes and approves its payload, invoke the appropriate
packer. Generate the MSIX manifest with final product fields in the build tree,
outside `$payload`; reserved MSIX metadata in the payload is rejected.

```powershell
if ($Format -eq 'Msi') {
    $package = & (Join-Path $tools 'msi/package.ps1') `
        -Config (Join-Path $root 'deployment/msi.json') -PayloadDirectory $payload `
        -Version $version -Architecture $Architecture `
        -OutputDirectory (Join-Path $buildRoot 'installer')
} else {
    # The consumer has already generated this manifest; do not copy it into payload.
    $package = & (Join-Path $tools 'msix/package.ps1') -PayloadDirectory $payload `
        -Manifest (Join-Path $buildRoot 'AppxManifest.xml') `
        -OutputDirectory (Join-Path $buildRoot 'installer')
}
$artifact = $package.Artifact
if ($sign) {
    $signed = & (Join-Path $tools 'signing/sign.ps1') -Artifact $artifact `
        @signingOptions -RequireTrusted:$RequireTrusted
}
```

`sign.ps1` verifies the resulting signature against the selected signer and, for
MSIX, validates the actual embedded publisher before signing. A separate
`verify.ps1` call is useful when accepting an existing signed artifact. Without
`RequireTrusted`, only `Valid` and `NotTrusted` signature statuses are accepted;
with it, SignTool must also accept the host's Authenticode trust policy. Choose
this explicitly for the consumer's distribution scenario. A failed sign/verify
aborts release and may leave changed bytes: rebuild rather than releasing them.

Never send PFX/password arguments through `Invoke-WbtTool` or print the signing
options. The shared signing operation bypasses that logger. For other native
product commands, use `Invoke-WbtTool -Tool ... -Arguments ... -LogPath ...` rather
than copying its exit-code/diagnostic handling. `Get-WbtSdkTool` discovers installed
MakeAppx/SignTool; it does not install or download an SDK.

### Compose consumer release metadata

Run the shared writer after successful signing/verification, or after inspection
for an unsigned artifact. Its `SHA256`, `Signed`, `SignatureStatus` and
`SignerThumbprint` describe actual final bytes. `SourceCommit`, `SourceDirty` and
`Version` are supplied by the consumer; the writer does not query Git. Metadata
inspection does not replace the explicit expected-signer/trust gate above.

If the consumer needs additional fields, first write an authoritative generic
sidecar, read it, and add only product-owned fields to a separate final manifest.
Do not rehash the artifact, call Authenticode again, or set `Signed` from the
requested signing flag. Do not overwrite shared fields or the generic sidecar.
Both files must remain outside the payload and the artifact must not change
between signing, metadata generation and publication.

This example preserves Agenda's `Format`, `Architecture` and legacy `Commit`
fields alongside every field from the generic record. `$commit` and `$sourceDirty`
come from the consumer's checked Git queries. The final manifest's `SchemaVersion`
continues to describe the shared fields; any additional consumer schema/version
policy belongs to the consumer.

```powershell
$metadata = & (Join-Path $tools 'common/write-artifact-manifest.ps1') `
    -Artifact $artifact -OutputPath (Join-Path $buildRoot 'artifact-metadata.json') `
    -Version $version -SourceCommit $commit -SourceDirty:$sourceDirty
$record = Get-Content -LiteralPath $metadata.Manifest -Raw | ConvertFrom-Json -AsHashtable
$record.Add('Format', $Format)
$record.Add('Architecture', $Architecture)
$record.Add('Commit', $record.SourceCommit) # Compatibility alias, not a second Git query.

. (Join-Path $tools 'common/Paths.ps1')
$manifest = Resolve-WbtPath (Join-Path $buildRoot 'release-artifacts.json')
Assert-WbtNoLinks $manifest
# CreateNew refuses an existing manifest, including a concurrent writer.
$stream = [IO.File]::Open($manifest, [IO.FileMode]::CreateNew,
    [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($record | ConvertTo-Json -Depth 10))
    $stream.Write($bytes)
} finally { $stream.Dispose() }
```

Keep existing consumer return fields too (for Agenda, `Artifact`, `Manifest`,
`Version` and `Commit`). Return `$manifest` as the consumer manifest path. File
serialization of the additive product record is consumer policy; hashing,
signature inspection and the original metadata record remain shared mechanisms.

### Explicit development certificates

Run these operations only when separately requested. They are never part of
build/package/sign or missing-certificate recovery. Consumer wrappers may pass
their subject/path defaults and forward `WhatIf`/`Confirm` to the shared commands.

```powershell
# From the consumer root; creates a new non-exportable key and exports only a CER.
./external/winbuildtools/signing/new-dev-certificate.ps1 `
    -Subject 'CN=Example.Development' -PublicCertificatePath C:/build/new-development.cer

# Separate elevated invocation, after reviewing the public certificate/thumbprint.
./external/winbuildtools/signing/trust-dev-certificate.ps1 `
    -CertificatePath C:/build/new-development.cer `
    -ExpectedThumbprint REVIEWED_40_HEX_THUMBPRINT -WhatIf
```

Creation uses CurrentUser/My and does not trust the key. Trust imports the reviewed
public certificate into LocalMachine/TrustedPeople, not Root. The trust command
requires administrator rights even with `WhatIf`. Consumers own production signing
and trust deployment/removal; they must not auto-create keys or auto-import trust.

## Build compatibility and migration acceptance

The packaging mechanisms can be migrated independently of .NET orchestration.
The generic .NET helper uses `--artifacts-path`, `--runtime` when requested, locked
restore and `--no-restore` build/publish. It rejects overrides of context-owned
properties. A project relying on a multi-RID lock graph or custom intermediate
layout must demonstrate compatible restore/build/publish behavior before switching.
For Agenda, preserve the existing `RuntimeIdentifier` property selection and
`AgendaPackagingRoot` isolation while that compatibility work is outstanding;
delegate native invocation/logging instead of copying the shared runner. This is
a product build exception, not a reason to retain generic signing/SDK/hash code.

Before removing old helpers, test the consumer's existing public commands,
missing-checkout errors, unsigned x64/ARM64 packaging, manifest/resource/license
preservation, signing option rejection and additive metadata compatibility. Live
signing/trust tests need explicitly approved disposable identities/environments;
do not use a developer's private key or mutate trust in ordinary automated tests.
Run `./external/winbuildtools/verify.ps1 -Integration` plus the consumer's own tests.
The shared synthetic tests do not establish the consumer's installer lifecycle,
ICE validation, native ARM64 execution or application correctness. Its pinned-clone
test exercises committed HEAD, so commit before relying on that part of acceptance.

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

Hosted verification remains manual-only. Do not add push/tag/schedule triggers or
dispatch Actions as a side effect of integration, packaging or publishing. Run
local checks normally; start a hosted workflow only on an explicit user request.

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
This guide does not migrate a consumer checkout; each application owns its adapter,
tests and pinned gitlink update.

## Public certificate validation before elevation

Dot-source signing/Certificates.ps1 from the pinned checkout. Read with
`Read-WbtPublicSigningCertificate -Path $cer -ExpectedThumbprint $reviewedThumbprint`;
ExpectedThumbprint is optional for initial inspection but required for trust import.
The reader is store-free, requires one public Cert in a .cer file of at most 1 MiB,
and checks current validity and explicit code-signing EKU. Dispose its returned
certificate in finally. It rejects PFX even when renamed to .cer.

For an explicitly requested trust change, call
`Import-WbtPublicSigningCertificate -Certificate $certificate -ExpectedThumbprint $reviewedThumbprint`.
It rechecks the object then adds that same object to LocalMachine/TrustedPeople,
never reopening the source path. WhatIf validates but never reaches store mutation
or elevation. The shared helper never launches UAC. A consumer UAC wrapper must
keep WhatIf unelevated, carry the reviewed thumbprint across the boundary and
re-read/revalidate the input after elevation before calling the object import.
Builds and packaging must never invoke trust setup automatically.
