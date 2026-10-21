#requires -Version 7.4

<#
.SYNOPSIS
Explicit certificate selection, artifact signing and signer verification.
.DESCRIPTION
Dot-source to load common helpers and define the signing operations. These
helpers never create certificates or import trust. Signing mutates the artifact;
a thrown post-sign verification error does not roll back the original bytes.
#>
. (Join-Path $PSScriptRoot '../common/Tools.ps1')
function Assert-WbtSigningOptions {
    # Reject ambiguous selectors before reading keys or touching artifact bytes.
    param([string]$CertificateThumbprint,[string]$CertificatePath,[string]$CertificatePassword,[string]$TimestampUri)
    if($CertificateThumbprint -and $CertificatePath) { throw 'Select a thumbprint or PFX, not both.' }
    if($CertificatePassword -and !$CertificatePath) { throw 'CertificatePassword requires a PFX path.' }
    if(!$CertificateThumbprint -and !$CertificatePath) { throw 'Signing requires an explicit certificate selection.' }
    if($CertificateThumbprint -and $CertificateThumbprint -notmatch '^[a-fA-F0-9]{40}$') { throw 'Certificate thumbprint must be exactly 40 hex characters.' }
    if($TimestampUri) {
        $uri=$null
        if(![uri]::TryCreate($TimestampUri,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Fragment) { throw 'TimestampUri must be an absolute HTTPS URL without credentials or fragments.' }
    }
}
function Assert-WbtSigningMetadata($Certificate,[string]$Publisher) {
    # Accept a plain metadata object so selection policy is testable without
    # using a real private key. The EKU OID below denotes code signing.
    if(!$Certificate.HasPrivateKey -or $Certificate.NotBefore -gt (Get-Date) -or $Certificate.NotAfter -le (Get-Date) -or '1.3.6.1.5.5.7.3.3' -notin $Certificate.UsageOids) { throw 'Select an unexpired code-signing certificate with its private key.' }
    if($Publisher -and $Certificate.Subject -cne $Publisher) { throw 'Package publisher and signing certificate subject must match.' }
}
function Get-WbtSigningCertificate {
    # Ownership transfers to the successful caller, which must Dispose(). On any
    # failure here, release the loaded certificate before propagating the error.
    param([string]$CertificateThumbprint,[string]$CertificatePath,[string]$CertificatePassword,[string]$Publisher)
    Assert-WbtSigningOptions -CertificateThumbprint $CertificateThumbprint -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword
    $certificate=$null
    try {
        if($CertificateThumbprint) { $certificate=Get-Item -LiteralPath "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction Stop }
        else {
            $path=Resolve-WbtPath $CertificatePath
            if(!(Test-Path -LiteralPath $path -PathType Leaf)) { throw 'PFX file does not exist.' }
            # A supplied PFX is loaded without persisting its key in a store.
            $certificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new($path,$CertificatePassword,[Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
        }
        $oids=@($certificate.Extensions | Where-Object { $_ -is [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension] } | ForEach-Object { $_.EnhancedKeyUsages } | ForEach-Object Value)
        Assert-WbtSigningMetadata ([pscustomobject]@{Subject=$certificate.Subject;HasPrivateKey=$certificate.HasPrivateKey;NotBefore=$certificate.NotBefore;NotAfter=$certificate.NotAfter;UsageOids=$oids}) $Publisher
        $certificate
    } catch { if($certificate) { $certificate.Dispose() }; throw }
}
function Get-WbtArtifactPublisher([string]$Artifact) {
    # MSIX binds publisher to the signing subject. Read the embedded manifest,
    # not a caller's source manifest; other supported artifact types return ''.
    if([IO.Path]::GetExtension($Artifact) -ine '.msix') { return '' }
    $archive=[IO.Compression.ZipFile]::OpenRead($Artifact)
    try {
        $entry=$archive.GetEntry('AppxManifest.xml')
        if(!$entry -or $entry.Length -gt 4MB) { throw 'Missing or oversized MSIX manifest.' }
        $stream=$entry.Open()
        $settings=[Xml.XmlReaderSettings]::new(); $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit; $settings.XmlResolver=$null
        $reader=[Xml.XmlReader]::Create($stream,$settings)
        try { $doc=[Xml.XmlDocument]::new(); $doc.XmlResolver=$null; $doc.Load($reader) } finally { $reader.Dispose(); $stream.Dispose() }
        $identity=$doc.DocumentElement.SelectSingleNode("*[local-name()='Identity']")
        if(!$identity -or !$identity.GetAttribute('Publisher')) { throw 'MSIX publisher missing.' }
        $identity.GetAttribute('Publisher')
    } finally { $archive.Dispose() }
}
function Test-WbtSignature {
    # Signer equality and accepted signature status are always checked. Chain
    # trust is an additional, explicit host-policy check, not implied by a key.
    param([string]$Artifact,[string]$CertificateThumbprint,[switch]$RequireTrusted)
    $path=Resolve-WbtPath $Artifact
    $signature=Get-AuthenticodeSignature -LiteralPath $path
    # Only known valid-integrity states are accepted. A development signature
    # can be untrusted; arbitrary UnknownError states are not treated as success.
    if(!$signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ine $CertificateThumbprint -or $signature.Status -notin @('Valid','NotTrusted')) { throw "Artifact signature verification failed: $($signature.Status)" }
    if($RequireTrusted) {
        $PSNativeCommandUseErrorActionPreference=$false
        & (Get-WbtSdkTool signtool.exe) verify /pa /v $path | Out-Host
        if($LASTEXITCODE -ne 0) { throw 'Trusted signature verification failed.' }
    }
    $signature
}
function Invoke-WbtSignature {
    param([string]$Artifact,[string]$CertificateThumbprint,[string]$CertificatePath,[string]$CertificatePassword,[string]$TimestampUri,[switch]$RequireTrusted)
    Assert-WbtSigningOptions -CertificateThumbprint $CertificateThumbprint -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -TimestampUri $TimestampUri
    $path=Resolve-WbtPath $Artifact
    Assert-WbtNoLinks $path
    if(!(Test-Path -LiteralPath $path -PathType Leaf) -or [IO.Path]::GetExtension($path) -notin @('.msi','.msix','.exe','.dll')) { throw 'Select an existing MSI, MSIX, EXE or DLL artifact.' }
    $publisher=Get-WbtArtifactPublisher $path
    $certificate=Get-WbtSigningCertificate -CertificateThumbprint $CertificateThumbprint -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -Publisher $publisher
    try {
        $tool=Get-WbtSdkTool signtool.exe
        # SHA-1 selects the certificate thumbprint; it is NOT the file digest.
        # Both artifact digest and optional RFC 3161 timestamp digest use SHA256.
        $arguments=@('sign','/fd','SHA256')
        if($CertificateThumbprint) { $arguments+=@('/sha1',$certificate.Thumbprint,'/s','My') }
        else {
            $arguments+=@('/f',(Resolve-WbtPath $CertificatePath))
            if($CertificatePassword) { $arguments+=@('/p',$CertificatePassword) }
        }
        if($TimestampUri) { $arguments+=@('/tr',$TimestampUri,'/td','SHA256') }
        # Never pass PFX arguments through the general diagnostic logger.
        $PSNativeCommandUseErrorActionPreference=$false
        & $tool @arguments $path | Out-Host
        if($LASTEXITCODE -ne 0) { throw 'Artifact signing failed; do not release this output.' }
        # Only report success after rereading the signature from the modified file.
        # The resulting hash supersedes every pre-signing inspection hash.
        $signature=Test-WbtSignature $path $certificate.Thumbprint -RequireTrusted:$RequireTrusted
        [pscustomobject]@{Artifact=$path;SHA256=(Get-FileHash -LiteralPath $path).Hash;SignerThumbprint=$certificate.Thumbprint;SignatureStatus=[string]$signature.Status;Publisher=$publisher}
    } finally { $certificate.Dispose() }
}
