# winbuildtools

Reusable Windows packaging and .NET build commands. MIT licensed. Designed to
be checked out at an exact Git revision inside application repositories.

| Directory | Provides |
| --- | --- |
| [msi](msi/README.md) | Native MSI authoring from strict JSON and cabinet/database inspection |
| msix | MSIX packing from a prepared payload/manifest and exact content inspection |
| signing | Explicit certificate signing/verification and separate development certificate utilities |
| common | SDK discovery, diagnostics and final artifact hash manifests |
| dotnet | Explicit locked restore and isolated build/publish operations |

Applications own their source, product configuration, manifests, branding,
required-file/privilege checks, dependency policy, signing identity and releases.
The tools do not fetch their own updates, choose application dependencies,
install products or automatically create/trust certificates during builds.

## Prerequisites

Windows 11 and PowerShell 7.4+. MSI uses Windows-provided Installer Automation,
MakeCab and Expand. MSIX/signing need Windows SDK 10.0.26100.0 or later with
MakeAppx/SignTool. .NET helpers additionally need a caller-installed supported
stable .NET SDK exposing the .NET 8+ artifacts layout. Git is needed for checkout
and integration tests. No runtime NuGet/npm/PowerShell packages are required.
See [dependencies](docs/DEPENDENCIES.md) for platform ownership and review limits.

## Use from another repository

Use a pinned Git submodule at external/winbuildtools. Initialize it as part of
checkout, not from a packaging script. See [integration](docs/INTEGRATION.md)
for adding the submodule, recursive cloning, private access, deliberate updates
and GitHub CI. A [consumer adapter](examples/consumer-package.ps1) demonstrates
an actionable missing-checkout error and script-relative product/tool paths.

## Package a prepared application

From the winbuildtools checkout (paths can be absolute):

```powershell
./msi/package.ps1 -Config C:/app/deployment/msi.json -PayloadDirectory C:/build/payload `
  -Version 1.2.3 -Architecture x64 -OutputDirectory C:/build/new-msi

./msix/package.ps1 -PayloadDirectory C:/build/payload `
  -Manifest C:/app/deployment/AppxManifest.xml -OutputDirectory C:/build/new-msix

./msix/inspect.ps1 -Artifact C:/build/app.msix -PayloadDirectory C:/build/payload `
  -Manifest C:/app/deployment/AppxManifest.xml -OutputDirectory C:/build/new-inspection
```

MSI supports x64/ARM64, machine installation and advertised Start-menu shortcuts.
Start with [msi/example.json](msi/example.json) and assign your own permanent
upgradeCode. [The MSI guide](msi/README.md) documents limits and identity rules.

MSIX consumes a complete caller-owned manifest without rewriting identity,
version, capabilities or extensions. Its payload must exclude AppxManifest.xml,
block maps, signatures and other container metadata; supply the authoritative
manifest separately. It stages a copy, leaves input unchanged and compares
manifest semantics, identity and payload bytes after unpacking. It also rejects
unexpected payload entries. Only standard generated container metadata is exempt.
Resource bundles, encryption and Store upload-file creation are outside this CLI.

Both package commands produce unsigned artifacts. Use a new output directory;
failed output remains available for diagnosis and must not be reused/released.
Unsigned MSIX needs appropriate signing/trust before direct installation.

## Explicit signing and final metadata

```powershell
./signing/sign.ps1 -Artifact C:/build/app.msi `
  -CertificateThumbprint YOUR_40_HEX_THUMBPRINT `
  -TimestampUri https://your-approved-timestamp-service -RequireTrusted

./common/write-artifact-manifest.ps1 -Artifact C:/build/app.msi `
  -OutputPath C:/build/release-artifacts.json -Version 1.2.3 -SourceCommit YOUR_SOURCE_COMMIT
```

Signing changes bytes in place and returns the new SHA-256. For MSIX, the
certificate subject must match the actual embedded publisher. Explicit PFX input
is also available. A signature check always validates expected signer/integrity;
-RequireTrusted additionally runs SignTool's platform trust policy. Development
NotTrusted signatures are permitted without that switch; unknown/error states
are rejected. No success result is returned after a signing/verification failure.
Regenerate final manifests after signing. See [security](SECURITY.md) for PFX
handling and the separately invoked certificate creation/trust commands.

## .NET operations

```powershell
./dotnet/invoke.ps1 -Operation Restore -Project C:/app/App.csproj -ArtifactsDirectory C:/build/intermediate
./dotnet/invoke.ps1 -Operation Build -Project C:/app/App.csproj -ArtifactsDirectory C:/build/intermediate
./dotnet/invoke.ps1 -Operation Publish -Project C:/app/App.csproj -ArtifactsDirectory C:/build/intermediate -OutputDirectory C:/build/payload
```

Use a committed lock file and the same project/configuration/runtime/properties
and artifact root for all operations. Restore uses --locked-mode; Build/Publish
use --no-restore. The helper requires an existing project lock before restore;
custom NuGetLockFilePath must be supplied in Properties. It accepts a single
csproj/fsproj/vbproj, not a solution. Consumers must also commit locks for all
referenced projects. The consumer owns SDK selection/global.json, NuGet configuration,
audit policy and application-specific isolation/resource workarounds. The helper
does not guarantee arbitrary project files honor every artifacts-path setting.
See [developers](DEVELOPERS.md) for parameters and logging.

## Verify and contribute

```powershell
./verify.ps1
./verify.ps1 -Integration
```

Verification uses synthetic payloads and never installs products or changes
certificate stores. Integration adds a small managed build and fresh recursive
submodule clone. GitHub verification runs **manually only** through Actions →
Verify → Run workflow after publication. See [validation](docs/VALIDATION.md),
[contributing](CONTRIBUTING.md), [security](SECURITY.md) and [publication](docs/GITHUB.md).

## License and provenance

[MIT License](LICENSE). Extracted from Agenda/ProcSight with the copyright holder's
explicit MIT relicensing authorization; retain [NOTICE.md](NOTICE.md). No Windows
SDK, framework/runtime or application redistribution rights are supplied by this
source license. Initial tool version: 0.1.0; no release has been published.
