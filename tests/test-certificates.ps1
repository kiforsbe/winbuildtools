#requires -Version 7.4
<#
.SYNOPSIS
Test bounded public certificate validation and object import without trust writes.
.DESCRIPTION
Certificates and RSA keys exist only in process memory. A mocked store boundary
proves path replacement cannot substitute an imported certificate. No elevation,
persistent key creation, real trust import or application signing is performed.
#>
. "$PSScriptRoot/TestSupport.ps1"
$root=Split-Path $PSScriptRoot -Parent
if(Test-Path "$root/signing/Certificates.ps1") { . "$root/signing/Certificates.ps1" }
Check ([bool](Get-Command Read-WbtPublicSigningCertificate -ErrorAction SilentlyContinue)) 'Missing bounded public certificate reader.'
$fixture=New-TestDirectory; $null=New-Item -ItemType Directory -Path $fixture
function New-FixtureCertificate([string]$Subject,[bool]$Eku=$true,[int]$Start=-1,[int]$End=1) {
 $key=[Security.Cryptography.RSA]::Create(2048)
 try {
  $request=[Security.Cryptography.X509Certificates.CertificateRequest]::new("CN=$Subject",$key,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
  if($Eku) {
   $oids=[Security.Cryptography.OidCollection]::new(); $null=$oids.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
   $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids,$false))
  }
  $request.CreateSelfSigned([DateTimeOffset]::Now.AddDays($Start),[DateTimeOffset]::Now.AddDays($End))
 } finally { $key.Dispose() }
}
$original=$null;$replacement=$null;$validated=$null;$bad=$null
try {
 $original=New-FixtureCertificate original; $replacement=New-FixtureCertificate replacement
 $path="$fixture/public.cer"
 [IO.File]::WriteAllBytes($path,$original.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
 $validated=Read-WbtPublicSigningCertificate $path $original.Thumbprint
 Check (!$validated.HasPrivateKey -and $validated.Thumbprint -ceq $original.Thumbprint) 'Owned public certificate returned.'
 foreach($arguments in @(@{Path=$path},@{Path=$path;ExpectedThumbprint=''})) {
  $withoutThumbprint=Read-WbtPublicSigningCertificate @arguments
  try { Check ($withoutThumbprint.Thumbprint -ceq $original.Thumbprint) 'Initial inspection permits absent/empty optional thumbprint.' } finally { $withoutThumbprint.Dispose() }
 }
 Rejected { Read-WbtPublicSigningCertificate $path ('0'*40) } 'thumbprint'
 Rejected { Read-WbtPublicSigningCertificate $path 'invalid' } 'thumbprint|pattern'
 [IO.File]::WriteAllBytes("$fixture/large.cer",[byte[]]::new(1MB+1))
 Rejected { Read-WbtPublicSigningCertificate "$fixture/large.cer" } 'MiB|size|limit'
 [IO.File]::WriteAllText("$fixture/invalid.cer",'invalid certificate bytes')
 Rejected { Read-WbtPublicSigningCertificate "$fixture/invalid.cer" } 'certificate|Cert'
 [IO.File]::WriteAllBytes("$fixture/private.cer",$original.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx))
 Rejected { Read-WbtPublicSigningCertificate "$fixture/private.cer" } 'public|Cert'
 foreach($variant in @(@('noeku',$false,-1,1),@('expired',$true,-3,-2),@('future',$true,1,2))) {
  $bad=New-FixtureCertificate $variant[0] $variant[1] $variant[2] $variant[3]
  try {
   [IO.File]::WriteAllBytes("$fixture/$($variant[0]).cer",$bad.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
   Rejected { Read-WbtPublicSigningCertificate "$fixture/$($variant[0]).cer" } 'signing|valid|current'
  } finally { $bad.Dispose();$bad=$null }
 }
 # Replace the path after validation; the import operation receives only the
 # already validated object and must not resolve or reopen that source path.
 [IO.File]::WriteAllBytes($path,$replacement.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
 $writer=${function:Write-WbtTrustedPeopleCertificate}
 $script:imported=$null
 function Write-WbtTrustedPeopleCertificate($Certificate) { $script:imported=$Certificate }
 try {
  $result=Import-WbtPublicSigningCertificate -Certificate $validated -ExpectedThumbprint $original.Thumbprint -Confirm:$false
  Check ([object]::ReferenceEquals($script:imported,$validated)) 'Import uses original validated object after path replacement.'
  Check ($result.Thumbprint -ceq $original.Thumbprint -and $result.Store -ceq 'LocalMachine/TrustedPeople') 'Fixed store result.'
  $script:imported=$null
  Import-WbtPublicSigningCertificate -Certificate $validated -ExpectedThumbprint $original.Thumbprint -WhatIf
  Check ($null -eq $script:imported) 'WhatIf never reaches store/elevation boundary.'
  Rejected { Import-WbtPublicSigningCertificate -Certificate $validated -ExpectedThumbprint $replacement.Thumbprint -Confirm:$false } 'thumbprint'
  Rejected { Import-WbtPublicSigningCertificate -Certificate $validated -ExpectedThumbprint '' -Confirm:$false } 'empty|pattern'
  Rejected { Import-WbtPublicSigningCertificate -Certificate $original -ExpectedThumbprint $original.Thumbprint -Confirm:$false } 'public'
 } finally { ${function:Write-WbtTrustedPeopleCertificate}=$writer }
 Write-Host 'Public certificate validation/import checks passed (ephemeral keys; mocked trust boundary).'
} finally {
 foreach($cert in @($original,$replacement,$validated,$bad)) { if($cert) { $cert.Dispose() } }
 Remove-TestDirectory $fixture
}
