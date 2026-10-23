#requires -Version 7.4
<#
.SYNOPSIS
Validate bounded public signing certificates and explicitly import validated objects.
.DESCRIPTION
Reading is unelevated and store-free. Read-WbtPublicSigningCertificate returns an
owned X509Certificate2; its caller must dispose it. An omitted or empty expected
thumbprint permits initial inspection. Import requires an exact thumbprint and that object,
revalidates it, and never reopens a source path. Only the separate store writer
requires administrator rights; -WhatIf stops before that boundary and never elevates.
#>
. (Join-Path $PSScriptRoot '../common/Paths.ps1')
function Assert-WbtPublicSigningCertificate {
 param([Parameter(Mandatory)][Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
       [ValidatePattern('^(?:[a-fA-F0-9]{40})?$')][string]$ExpectedThumbprint)
 if($ExpectedThumbprint -and $Certificate.Thumbprint -ine $ExpectedThumbprint) { throw 'Certificate thumbprint does not match the reviewed identity.' }
 $now=Get-Date
 $oids=@(foreach($extension in $Certificate.Extensions) {
  if($extension -is [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) {
   foreach($oid in $extension.EnhancedKeyUsages) { $oid.Value }
  }
 })
 if($Certificate.HasPrivateKey -or $Certificate.NotBefore -gt $now -or $Certificate.NotAfter -le $now -or '1.3.6.1.5.5.7.3.3' -notin $oids) { throw 'Certificate must be public, currently valid and explicitly permit code-signing.' }
}
function Read-WbtPublicSigningCertificate {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$Path,
       [ValidatePattern('^(?:[a-fA-F0-9]{40})?$')][string]$ExpectedThumbprint)
 $resolved=Resolve-WbtPath $Path
 Assert-WbtNoLinks $resolved
 if([IO.Path]::GetExtension($resolved) -ine '.cer') { throw 'Select a public .cer certificate file.' }
 $stream=$null;$certificate=$null
 try {
  # One bounded read of one open handle. FileShare.Read prevents concurrent
  # replacement while reading on Windows; importing later uses only this object.
  $stream=[IO.FileStream]::new($resolved,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  if($stream.Length -le 0 -or $stream.Length -gt 1MB) { throw 'Public certificate size must be 1 byte through 1 MiB.' }
  $bytes=[byte[]]::new([int]$stream.Length)
  $stream.ReadExactly($bytes,0,$bytes.Length)
  if($stream.ReadByte() -ne -1) { throw 'Certificate exceeds the read limit.' }
  if([Security.Cryptography.X509Certificates.X509Certificate2]::GetCertContentType($bytes) -ne [Security.Cryptography.X509Certificates.X509ContentType]::Cert) { throw 'Input must contain one public Cert, not PFX/PKCS7/serialized certificate data.' }
  # The byte constructor preserves the PowerShell 7.4 / .NET 8 API floor.
  # Do not use a file constructor or let private-key containers reach this point.
  $certificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes)
  Assert-WbtPublicSigningCertificate $certificate $ExpectedThumbprint
  $result=$certificate; $certificate=$null
  return $result
 } finally { if($stream) { $stream.Dispose() }; if($certificate) { $certificate.Dispose() } }
}
function Write-WbtTrustedPeopleCertificate {
 param([Parameter(Mandatory)][Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
 # This is the only mutation boundary. It accepts no file path/store choice and
 # never requests elevation. Wrappers own any explicit UAC orchestration.
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 try { $principal=[Security.Principal.WindowsPrincipal]::new($identity); $admin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } finally { $identity.Dispose() }
 if(!$admin) { throw 'Administrator rights are required to import LocalMachine/TrustedPeople.' }
 $store=[Security.Cryptography.X509Certificates.X509Store]::new('TrustedPeople',[Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
 try {
  $store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
  $store.Add($Certificate)
  $certificates=$store.Certificates
  try {
   $found=$false
   foreach($entry in $certificates) { if($entry.Thumbprint -ceq $Certificate.Thumbprint) { $found=$true } }
   if(!$found) { throw 'Certificate trust import did not succeed.' }
  } finally { foreach($entry in $certificates) { $entry.Dispose() } }
 } finally { $store.Dispose() }
}
function Import-WbtPublicSigningCertificate {
 [CmdletBinding(SupportsShouldProcess)]
 param([Parameter(Mandatory)][Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
       [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$ExpectedThumbprint)
 # Recheck dates/EKU/identity after possible UAC delay. Keep ownership with the
 # caller and send the SAME object to the writer; there is no path to reopen.
 Assert-WbtPublicSigningCertificate $Certificate $ExpectedThumbprint
 if($PSCmdlet.ShouldProcess("LocalMachine/TrustedPeople: $($Certificate.Subject) [$ExpectedThumbprint]",'Trust development signing certificate')) {
  Write-WbtTrustedPeopleCertificate $Certificate
  [pscustomobject]@{Thumbprint=$Certificate.Thumbprint;Store='LocalMachine/TrustedPeople'}
 }
}
