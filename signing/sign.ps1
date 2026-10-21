#requires -Version 7.4

<#
.SYNOPSIS
Signs an artifact using an explicitly selected code-signing certificate.
.DESCRIPTION
Uses exactly one CurrentUser/My thumbprint or PFX. MSIX subject matching is
checked against its embedded publisher. Does not create keys or import trust.
Signing changes the artifact in place; publish only after success and regenerate
final hash manifests afterward. Prefer thumbprints over command-line PFX secrets.
.PARAMETER Artifact
Existing MSI, MSIX, EXE or DLL to modify in place.
.PARAMETER CertificateThumbprint
Exactly 40 hex characters selecting an existing CurrentUser/My certificate.
.PARAMETER CertificatePath
PFX path as an alternative to CertificateThumbprint; never imported persistently.
.PARAMETER CertificatePassword
Optional PFX password. Passed to SignTool; do not log the command or arguments.
.PARAMETER TimestampUri
Optional absolute HTTPS RFC 3161 timestamp endpoint, without credentials/fragments.
.PARAMETER RequireTrusted
Also require signtool verify /pa to succeed against this host's trust policy.
.OUTPUTS
Object: Artifact, SHA256, SignerThumbprint, SignatureStatus and Publisher.
.EXAMPLE
./signing/sign.ps1 -Artifact C:/build/app.msix -CertificateThumbprint YOUR_40_HEX_THUMBPRINT -TimestampUri https://your-approved-timestamp-service
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact,[string]$CertificateThumbprint,[string]$CertificatePath,[string]$CertificatePassword,[string]$TimestampUri,[switch]$RequireTrusted)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Signing.ps1')
# Forward only caller-bound options; defaults and policy stay in the shared helper.
Invoke-WbtSignature @PSBoundParameters
