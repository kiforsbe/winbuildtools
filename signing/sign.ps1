#requires -Version 7.4
<#
.SYNOPSIS
Signs an artifact using an explicitly selected code-signing certificate.
.DESCRIPTION
Uses exactly one CurrentUser/My thumbprint or PFX. MSIX subject matching is
checked against its embedded publisher. Does not create keys or import trust.
Signing changes the artifact in place; publish only after success and regenerate
final hash manifests afterward. Prefer thumbprints over command-line PFX secrets.
.PARAMETER RequireTrusted
Also require signtool verify /pa to succeed against this host's trust policy.
.EXAMPLE
./signing/sign.ps1 -Artifact C:/build/app.msix -CertificateThumbprint YOUR_40_HEX_THUMBPRINT -TimestampUri https://your-approved-timestamp-service
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact,[string]$CertificateThumbprint,[string]$CertificatePath,[string]$CertificatePassword,[string]$TimestampUri,[switch]$RequireTrusted)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Signing.ps1')
Invoke-WbtSignature @PSBoundParameters
