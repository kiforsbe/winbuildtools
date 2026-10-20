# Security

This tooling processes build inputs and can create installers with machine-wide
effects when subsequently installed. Review payload/configuration and output
before release. Synthetic inspection does not establish an application's safety,
permission suitability, dependency security, license rights or installed behavior.

No private reporting address or GitHub private-reporting setting is configured
by this local setup. Before public hosting, maintainers must configure a private
channel and update this file. Until then, contact the maintainer through an
already-established private channel; do not post secrets or exploit details in
public issues. No response-time/support guarantee is claimed.

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
The automated tests do not create, sign with or trust a certificate.

## Build and checkout inputs

Pin external tooling commits. Review updates before changing the consumer gitlink.
Do not store access tokens in URLs or .gitmodules. Logs contain full tool output;
do not supply secret values through MSBuild properties. Manifests/configs remain
data, but project files/build targets are executable code and require trust.

There are no vendored package dependencies. Installed Git, PowerShell, .NET,
Windows and SDK components require their own support/security updates. No advisory
scan or test result establishes complete security. See [dependencies](docs/DEPENDENCIES.md).
