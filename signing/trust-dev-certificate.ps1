#requires -Version 7.4
#requires -RunAsAdministrator
<#
.SYNOPSIS
Explicitly trusts one reviewed public development signing certificate.
.DESCRIPTION
Administrator-only import into LocalMachine/TrustedPeople, never Root. Requires
the exact expected thumbprint. Run separately from builds and packaging; review
the certificate identity and intended deployment scope first. Supports -WhatIf.
.EXAMPLE
./signing/trust-dev-certificate.ps1 -CertificatePath C:/build/development.cer -ExpectedThumbprint YOUR_40_HEX_THUMBPRINT
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$CertificatePath,[Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$ExpectedThumbprint)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../common/Paths.ps1')
$path=Resolve-WbtPath $CertificatePath
Assert-WbtNoLinks $path
if([IO.Path]::GetExtension($path) -ine '.cer') { throw 'Select a public .cer file.' }
$certificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new($path)
try {
    $oids=@($certificate.Extensions | Where-Object { $_ -is [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension] } | ForEach-Object { $_.EnhancedKeyUsages } | ForEach-Object Value)
    if($certificate.Thumbprint -ine $ExpectedThumbprint -or $certificate.HasPrivateKey -or $certificate.NotBefore -gt (Get-Date) -or $certificate.NotAfter -le (Get-Date) -or '1.3.6.1.5.5.7.3.3' -notin $oids) { throw 'Certificate must match the reviewed thumbprint and be a current public code-signing certificate.' }
    if($PSCmdlet.ShouldProcess("LocalMachine/TrustedPeople: $($certificate.Subject) [$ExpectedThumbprint]",'Trust development signing certificate')) {
        $null=Import-Certificate -FilePath $path -CertStoreLocation Cert:/LocalMachine/TrustedPeople
        if(!(Test-Path -LiteralPath "Cert:/LocalMachine/TrustedPeople/$ExpectedThumbprint")) { throw 'Certificate trust import did not succeed.' }
        [pscustomobject]@{Thumbprint=$ExpectedThumbprint;Store='LocalMachine/TrustedPeople'}
    }
} finally { $certificate.Dispose() }
