#requires -Version 7.4
<#
.SYNOPSIS
Explicitly creates a non-exportable development signing key and public CER.
.DESCRIPTION
Creates a one-year SHA-256 code-signing certificate in CurrentUser/My. Does not
trust it or export its private key. Run only when a new development key is wanted.
PublicCertificatePath must be new. Production signing policy belongs to consumers.
.EXAMPLE
./signing/new-dev-certificate.ps1 -Subject 'CN=Example.Development' -PublicCertificatePath C:/build/example-development.cer
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$Subject,[Parameter(Mandatory)][string]$PublicCertificatePath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../common/Paths.ps1')
$path=Resolve-WbtPath $PublicCertificatePath
Assert-WbtNoLinks $path
if(Test-Path -LiteralPath $path) { throw 'Public certificate output already exists.' }
if([IO.Path]::GetExtension($path) -ine '.cer') { throw 'PublicCertificatePath must end in .cer.' }
if(!$Subject.StartsWith('CN=')) { throw 'Provide an explicit development subject starting with CN=.' }
$null=[Security.Cryptography.X509Certificates.X500DistinguishedName]::new($Subject)
if($PSCmdlet.ShouldProcess("CurrentUser/My: $Subject",'Create development code-signing key and export public certificate')) {
    $null=New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force
    $certificate=New-SelfSignedCertificate -Type Custom -Subject $Subject -FriendlyName "$Subject development signing" -CertStoreLocation Cert:/CurrentUser/My -KeyExportPolicy NonExportable -HashAlgorithm SHA256 -KeyUsage DigitalSignature -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3') -NotAfter (Get-Date).AddYears(1)
    try {
        Export-Certificate -Cert $certificate -FilePath $path -Type CERT | Out-Null
        [pscustomobject]@{Thumbprint=$certificate.Thumbprint;Subject=$certificate.Subject;PublicCertificate=$path;Trusted=$false}
    } finally { $certificate.Dispose() }
}
