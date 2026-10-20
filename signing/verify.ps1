#requires -Version 7.4
<#
.SYNOPSIS
Verifies signature integrity and signer identity, optionally requiring trust.
.EXAMPLE
./signing/verify.ps1 -Artifact C:/build/app.msi -CertificateThumbprint YOUR_40_HEX_THUMBPRINT -RequireTrusted
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact,[Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$CertificateThumbprint,[switch]$RequireTrusted)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Signing.ps1')
$signature=Test-WbtSignature $Artifact $CertificateThumbprint -RequireTrusted:$RequireTrusted
[pscustomobject]@{Artifact=(Resolve-WbtPath $Artifact);SHA256=(Get-FileHash -LiteralPath $Artifact).Hash;SignerThumbprint=$signature.SignerCertificate.Thumbprint;SignatureStatus=[string]$signature.Status}
