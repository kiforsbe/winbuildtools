# Security

This tooling processes build inputs and can create installers with machine-wide
effects when subsequently installed. Review payload/configuration and output
before release. Synthetic inspection does not establish an application's safety,
permission suitability, dependency security, license rights or installed behavior.

Report suspected vulnerabilities through GitHub's
[private vulnerability reporting](https://github.com/kiforsbe/winbuildtools/security/advisories/new),
which is enabled for this repository. Do not post secrets or exploit details in
public issues. No response-time/support guarantee is claimed.

## MSI maintenance and running applications

V1 and v2 graceful MSIs use Windows Installer's Restart Manager to request normal
shutdown of applications using affected files. Full UI requires explicit consent;
basic/reduced UI follows the native prompt and silent deployment can request
shutdown without prompting. Forced termination and automatic relaunch are not
authored. Machine policy, app cooperation and reboot requirements still apply.
Consumers must implement safe shutdown/state persistence, including tray apps,
and validate the actual installed lifecycle on an authorized disposable host.
See [maintenance policy](msi/README.md#running-applications). Non-installing
verification disables Restart Manager in isolated preflight copies; it never
requests shutdown of real applications.

V2 consumers explicitly select disabled or graceful servicing and own persistent
GUIDs and exact directories. Complete configured MSI semantics are checked before
costing/extraction, including upgrade rules and destinations. Scope choice uses
native MSI tables and does not migrate existing registrations between contexts.

The native wizard authors three exact type-51 property setters (folder restoration
and ARP location), one executable-component-owned registry value for folder memory,
and shortcut property-store metadata invoking native product uninstall. Inspection
rejects changed/extra action or registry rows before preflight; this does not allow
executable/script custom actions. Preflight also randomizes the folder-memory keys
and disables RM before engine entry, so it cannot read the actual product's record.
Selected destination and license acceptance are secured for restricted elevated
UI-to-server transfer. These properties are data, not a privilege/sandbox boundary.
Consumer license text is escaped plain text, never accepted RTF objects/commands.

Inactive native preview is read-only. The acceptance helper's default only builds
fresh-identity fixtures; its real lifecycle requires both `-RunLifecycle` and
`-DisposableHost`, accepts no supplied ProductCode, and must be run on an isolated
Windows installation. It is excluded from ordinary verification. See
[acceptance boundaries](docs/MSI-ACCEPTANCE.md).

## Certificates and signatures

Build/pack commands never create keys or change trust. Signing selects exactly
one existing CurrentUser/My certificate or supplied PFX. PFX keys are inspected
with ephemeral import; the SignTool PFX password is passed to the child process
and may be visible to privileged process inspection. Prefer a store thumbprint
and approved secure signing infrastructure. Never commit keys, passwords or tokens.

Certificate checks require a current validity interval, private key, code-signing
EKU and matching MSIX subject. Signature verification checks the expected signer
and accepts only Valid/NotTrusted integrity states. Use -RequireTrusted for the
host's SignTool trust policy; a locally untrusted development signature is not
public distribution trust. A failed signing command may leave changed bytes;
discard/rebuild that artifact and never release after failure. Hash manifests
must describe final signed bytes and are not themselves signed attestations.

Development key creation is separate and explicit:

```powershell
$certificate = ./signing/new-dev-certificate.ps1 -Subject 'CN=Example.Development' -PublicCertificatePath C:/build/development.cer
```

This creates a one-year non-exportable key in CurrentUser/My and exports only
the public CER. It does not install trust. Review the subject/thumbprint before
the separate administrative operation:

```powershell
./signing/trust-dev-certificate.ps1 -CertificatePath C:/build/development.cer -ExpectedThumbprint $certificate.Thumbprint -WhatIf
# Run without -WhatIf only when the reviewed trust change is intended.
```

Trust imports only into LocalMachine/TrustedPeople, never Root, and requires an
administrator. Consumers own trust deployment/removal and production signing.
Public certificate validation reads at most 1 MiB once, checks actual Cert content
type, public-only status, validity, explicit code-signing EKU and the optional
expected thumbprint. Trust import requires that thumbprint and adds the same
validated in-memory object; it never reopens the path after validation. The helper
never elevates and WhatIf stops before the admin/store boundary. Tests generate
only ephemeral in-memory keys/certificates and mock the writer; they do not
create persistent keys, sign application artifacts or mutate trust.

## Build and checkout inputs

Pin external tooling commits. Review updates before changing the consumer gitlink.
Do not store access tokens in URLs or .gitmodules. Logs contain full tool output;
do not supply secret values through MSBuild properties. Manifests/configs remain
data, but project files/build targets are executable code and require trust.

There are no vendored package dependencies. Installed Git, PowerShell, .NET,
Windows and SDK components require their own support/security updates. No advisory
scan or test result establishes complete security. See [dependencies](docs/DEPENDENCIES.md).
