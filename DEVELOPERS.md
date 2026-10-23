# Developing winbuildtools

Read [ARCHITECTURE.md](ARCHITECTURE.md) for module ownership, packaging/build
flows, failure semantics and the constraints to preserve when changing scripts.

Use Windows 11, PowerShell 7.4+ and Windows SDK 10.0.26100.0+. Optional .NET
integration requires an installed stable supported SDK with .NET 8+ CLI features;
select it through your environment/global.json. No modules need to be restored.

```powershell
./verify.ps1
./verify.ps1 -Integration
git diff --check
```

Keep engine files under msi/ self-contained. Shared helpers under common/ are
used by msix/, signing/ and dotnet/. Do not introduce imports back into Agenda or
ProcSight. Product-specific inputs and production/release policies stay outside
this repository. Examples use synthetic identities and no real application code.

## Public contracts

| Command | Main inputs | Result |
| --- | --- | --- |
| msi/package.ps1 | Config, PayloadDirectory, Version, Architecture, new OutputDirectory | Artifact, Version, Architecture, SHA256, InspectionReport |
| msix/package.ps1 | PayloadDirectory, Manifest, new OutputDirectory | Artifact, Name, Publisher, Version, Architecture, SHA256, InspectionDirectory |
| msix/inspect.ps1 | Artifact plus expected PayloadDirectory/Manifest, new OutputDirectory | Same inspection result |
| signing/sign.ps1 | Artifact and CertificateThumbprint or CertificatePath; optional password/timestamp/trust | Artifact, SHA256, SignerThumbprint, SignatureStatus, Publisher |
| signing/verify.ps1 | Artifact, expected CertificateThumbprint; optional RequireTrusted | Artifact, SHA256, SignerThumbprint, SignatureStatus |
| common/write-artifact-manifest.ps1 | Artifact, new OutputPath; source/version fields | Artifact, Manifest, SHA256 |
| dotnet/invoke.ps1 | Operation, Project, ArtifactsDirectory; context below | Operation, Project, ArtifactsDirectory, OutputDirectory, LogPath |

Paths resolve against the caller's PowerShell filesystem location. Script-relative
tool/product resolution is the consumer adapter's responsibility. Paths with
spaces are supported. Inputs and output ancestors reject reparse points in shared
packaging operations. MSI retains its own strict JSON/path rules.

.NET context: Operation is Restore, Build or Publish; Configuration defaults to
Release. Optional RuntimeIdentifier, Properties (scalar MSBuild name/value map),
NuGetConfig, DotnetPath and LogPath are explicit inputs. Publish accepts a new
OutputDirectory; do not publish into source or intermediate directories. Keep
context identical across operations. The helper changes location to the project
directory so consumer SDK selection is honored, then restores the caller location.
Pass a single csproj/fsproj/vbproj. Restore preflight requires packages.lock.json
beside it, or the existing custom NuGetLockFilePath explicitly supplied in
Properties. NuGet's --locked-mode alone does not guarantee a lock exists; the
helper additionally enables RestorePackagesWithLockFile. Consumers must commit
locks for referenced projects and validate any imported custom lock policy.
Complex/list MSBuild settings belong in project files: property names must be
identifiers; values containing comma/semicolon separators or newlines and overrides of context-owned
paths/configuration/runtime/locked mode are rejected. Project files still control
their own behavior. No automatic application tests or policy decisions are inferred.

Invoke-WbtTool saves full child output to an explicit log and prints concise
success/failure summaries. It never prints arguments. Secret-bearing signing
commands bypass that logger; do not supply secret-bearing properties to builds.
MSIX logs live under the new output tree. .NET logs default under
ArtifactsDirectory/logs with unique names. Keep failed output for diagnosis and
choose a new path on retry. Signatures change package bytes: recompute release
metadata after signing and do not treat an earlier inspection hash as final.

## Compatibility and releases

MSI maintenance policy and application shutdown requirements are documented in
[Running applications](msi/README.md#running-applications). Table inspection and
isolated costing are not installed lifecycle acceptance. Do not add application
termination custom actions or run a shutdown/install transaction during automated
verification. An installed older MSI keeps its cached policy until a separately
validated servicing path replaces it.

Tool version 0.3.0 (`v0.3.0`) retains the command, configuration and result-field
contracts, and changes newly authored MSI maintenance to the Restart Manager
policy above. Inspection now requires its maintenance policy and native UI tables.
Applications must implement graceful Windows shutdown and validate servicing;
older built/cached MSIs are unchanged. Hosted at
[kiforsbe/winbuildtools](https://github.com/kiforsbe/winbuildtools).
Config schemaVersion 1 remains supported unchanged. The new opt-in v2 contract
accepts literal ProductCode/UpgradeCode/component GUIDs, architecture, exact install/
menu names, user/machine/choice scope and explicit Restart Manager policy; see
[the v2 guide](msi/README.md#configuration-version-2). Scope.ps1 owns native
context/chooser tables; Semantics.ps1 compares complete configured table and summary
semantics before any costing or extraction. New helper files stay inside msi/.

`signing/Certificates.ps1` exposes store-free
`Read-WbtPublicSigningCertificate(Path, ExpectedThumbprint optional)` returning an
owned certificate. Dispose it in finally. `Import-WbtPublicSigningCertificate` takes
that object and mandatory ExpectedThumbprint, revalidates it and supports WhatIf/
Confirm. Only its fixed LocalMachine/TrustedPeople writer requires administrator
rights; helpers never request elevation or reopen a certificate path. Consumer
wrappers own explicit UAC orchestration and thumbprint continuity.
Breaking CLI/result/schema changes require a documented
versioning decision; keep historical commits available for consumers. Start with
0.x releases while the contract is being adopted, document changes in CHANGELOG,
and publish tags only after verification and review. No build follows a branch
head automatically. See [GitHub setup](docs/GITHUB.md).

Keep tests independent and non-installing. Native tests exercise tables, cabinets
and read-only costing preflight with isolated identities. See the explicit
[validation limits](docs/VALIDATION.md). Test-first changes should cover observable
failure behavior as well as successful package creation.

Native setup now lives in `msi/Wizard.ps1`; `Registration.ps1` owns bounded
shortcut/ARP metadata, context-specific folder memory and the exact three type-51
setters. There are no executable custom actions. `INSTALLFOLDER` and license
acceptance are secure UI-to-server properties. Keep selection before discovery/
costing and native repair/remove feature events after costing. Do not add generic
property setters or weaken semantic comparison to accommodate a new table.
`msi/preview.ps1` requires STA and displays inactive native dialogs without an
install session. The separately opted-in `msi/tests/acceptance.ps1 -RunLifecycle
-DisposableHost` performs real synthetic servicing only on an isolated host;
it is never invoked by verification or CI. See [acceptance](docs/MSI-ACCEPTANCE.md).
