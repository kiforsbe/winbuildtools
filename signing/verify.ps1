#requires -Version 7.4

<#
.SYNOPSIS
Verifies signature integrity and signer identity, optionally requiring trust.
.DESCRIPTION
Reads an existing artifact without modifying it. Valid and NotTrusted signature
states are accepted for the expected signer unless RequireTrusted is requested.
.PARAMETER Artifact
Existing signed artifact; no package-content or application checks are performed.
.PARAMETER CertificateThumbprint
Expected signer's 40-character hexadecimal thumbprint, not an automatic selector.
.PARAMETER RequireTrusted
Additionally require SignTool's Authenticode policy verification on this host.
.OUTPUTS
Object: Artifact, SHA256, SignerThumbprint and SignatureStatus.
.EXAMPLE
./signing/verify.ps1 -Artifact C:/build/app.msi -CertificateThumbprint YOUR_40_HEX_THUMBPRINT -RequireTrusted
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact,[Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$CertificateThumbprint,[switch]$RequireTrusted)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Signing.ps1')
# Emit metadata only after the signature gate succeeds; no best-effort result.
$signature=Test-WbtSignature $Artifact $CertificateThumbprint -RequireTrusted:$RequireTrusted
[pscustomobject]@{Artifact=(Resolve-WbtPath $Artifact);SHA256=(Get-FileHash -LiteralPath $Artifact).Hash;SignerThumbprint=$signature.SignerCertificate.Thumbprint;SignatureStatus=[string]$signature.Status}
