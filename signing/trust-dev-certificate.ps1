#requires -Version 7.4
#requires -RunAsAdministrator

<#
.SYNOPSIS
Explicitly trusts one reviewed public development signing certificate.
.DESCRIPTION
Administrator-only import into LocalMachine/TrustedPeople, never Root. Requires
the exact expected thumbprint. Run separately from builds and packaging; review
the certificate identity and intended deployment scope first. Supports -WhatIf.
.PARAMETER CertificatePath
Reviewed public .cer file with a current validity interval and code-signing EKU.
.PARAMETER ExpectedThumbprint
Exact 40-character hexadecimal thumbprint obtained through a trusted channel.
.OUTPUTS
Object: Thumbprint and Store after successful import; no result under WhatIf.
.EXAMPLE
./signing/trust-dev-certificate.ps1 -CertificatePath C:/build/development.cer -ExpectedThumbprint YOUR_40_HEX_THUMBPRINT
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$CertificatePath,[Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$ExpectedThumbprint)
$ErrorActionPreference='Stop'
# Validation is store-free. The separate helper imports the owned object, never
# reopens the path after thumbprint/content validation. Forward WhatIf/Confirm.
. (Join-Path $PSScriptRoot 'Certificates.ps1')
$certificate=Read-WbtPublicSigningCertificate -Path $CertificatePath -ExpectedThumbprint $ExpectedThumbprint
try {
    if($PSCmdlet.ShouldProcess("LocalMachine/TrustedPeople: $($certificate.Subject) [$ExpectedThumbprint]",'Trust development signing certificate')) {
        Import-WbtPublicSigningCertificate -Certificate $certificate -ExpectedThumbprint $ExpectedThumbprint -Confirm:$false
    }
} finally { $certificate.Dispose() }
