#requires -Version 7.4

<#
.SYNOPSIS
Write new JSON metadata describing the artifact's current bytes.
.DESCRIPTION
Dot-source to define Write-WbtArtifactManifest. Source/version fields are supplied
by the consumer; neither source cleanliness nor trust is established here.
#>
. (Join-Path $PSScriptRoot 'Paths.ps1')
function Write-WbtArtifactManifest {
    # Hash after all byte-changing steps, particularly signing. Return only the
    # artifact/manifest paths and hash; the richer record lives in the JSON file.
    param([string]$Artifact,[string]$OutputPath,[string]$Version,[string]$SourceCommit,[switch]$SourceDirty)
    $artifactPath=Resolve-WbtPath $Artifact
    $output=Resolve-WbtPath $OutputPath
    Assert-WbtNoLinks $artifactPath; Assert-WbtNoLinks $output
    if(!(Test-Path -LiteralPath $artifactPath -PathType Leaf)) { throw 'Artifact file not found.' }
    if(Test-Path -LiteralPath $output) { throw 'Manifest output already exists.' }
    # Inspect actual bytes rather than trusting a caller-supplied Signed flag.
    $signature=Get-AuthenticodeSignature -LiteralPath $artifactPath
    $thumbprint=if($signature.SignerCertificate) { $signature.SignerCertificate.Thumbprint } else { $null }
    $record=[ordered]@{SchemaVersion=1;Artifact=[IO.Path]::GetFileName($artifactPath);Version=$Version;SourceCommit=$SourceCommit;SourceDirty=[bool]$SourceDirty;SHA256=(Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash;Signed=([bool]$signature.SignerCertificate -and $signature.Status -in @('Valid','NotTrusted'));SignatureStatus=[string]$signature.Status;SignerThumbprint=$thumbprint}
    $json=$record | ConvertTo-Json
    # CreateNew avoids overwriting previous release metadata, even on races.
    $stream=[IO.File]::Open($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json); $stream.Write($bytes) } finally { $stream.Dispose() }
    [pscustomobject]@{Artifact=$artifactPath;Manifest=$output;SHA256=$record.SHA256}
}
