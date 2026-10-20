#requires -Version 7.4
. "$PSScriptRoot/TestSupport.ps1"
$root=Split-Path $PSScriptRoot -Parent
if(Test-Path "$root/signing/Signing.ps1") { . "$root/signing/Signing.ps1" }
Check ([bool](Get-Command Assert-WbtSigningOptions -ErrorAction SilentlyContinue)) 'Missing generic signing validation.'
Assert-WbtSigningOptions -CertificateThumbprint ('a'*40)
Rejected { Assert-WbtSigningOptions } 'explicit'
Rejected { Assert-WbtSigningOptions -CertificateThumbprint 'invalid' } 'thumbprint'
Rejected { Assert-WbtSigningOptions -CertificateThumbprint ('a'*40) -CertificatePath 'a.pfx' } 'both'
Rejected { Assert-WbtSigningOptions -CertificatePassword 'orphan' } 'requires'
Rejected { Assert-WbtSigningOptions -CertificateThumbprint ('a'*40) -TimestampUri 'http://example.test' } 'HTTPS'
Rejected { Assert-WbtSigningOptions -CertificateThumbprint ('a'*40) -TimestampUri 'https://user:pass@example.test' } 'HTTPS'
$metadata=[pscustomobject]@{Subject='CN=Example';HasPrivateKey=$true;NotBefore=(Get-Date).AddDays(-1);NotAfter=(Get-Date).AddDays(1);UsageOids=@('1.3.6.1.5.5.7.3.3')}
Assert-WbtSigningMetadata $metadata 'CN=Example'
Rejected { Assert-WbtSigningMetadata $metadata 'CN=Other' } 'publisher'
$metadata.HasPrivateKey=$false
Rejected { Assert-WbtSigningMetadata $metadata } 'private key'
$metadata.HasPrivateKey=$true; $metadata.NotAfter=(Get-Date).AddDays(-1)
Rejected { Assert-WbtSigningMetadata $metadata } 'unexpired'
$metadata.NotAfter=(Get-Date).AddDays(1); $metadata.NotBefore=(Get-Date).AddDays(1)
Rejected { Assert-WbtSigningMetadata $metadata } 'unexpired'
$metadata.NotBefore=(Get-Date).AddDays(-1); $metadata.UsageOids=@()
Rejected { Assert-WbtSigningMetadata $metadata } 'code-signing'
$fixture=New-TestDirectory
$null=New-Item -ItemType Directory -Path $fixture
try {
    Set-Content "$fixture/unsigned.msi" 'unsigned synthetic bytes'
    $before=(Get-FileHash "$fixture/unsigned.msi").Hash
    $storeBefore=@(Get-ChildItem Cert:/CurrentUser/My | ForEach-Object Thumbprint | Sort-Object)
    Rejected { & "$root/signing/sign.ps1" -Artifact "$fixture/unsigned.msi" -CertificatePath "$fixture/missing.pfx" } 'exist|find'
    Rejected { Test-WbtSignature "$fixture/unsigned.msi" ('a'*40) } 'signature'
    Check ((Get-FileHash "$fixture/unsigned.msi").Hash -eq $before) 'Failed preflight preserves artifact bytes.'
    $storeAfter=@(Get-ChildItem Cert:/CurrentUser/My | ForEach-Object Thumbprint | Sort-Object)
    Check (($storeBefore -join ',') -ceq ($storeAfter -join ',')) 'Signing failure leaves key store unchanged.'
    Write-Host 'Signing validation checks passed (no key created, trusted or used).'
} finally { Remove-TestDirectory $fixture }
