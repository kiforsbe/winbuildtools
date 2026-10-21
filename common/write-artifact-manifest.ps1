#requires -Version 7.4

<#
.SYNOPSIS
Records final artifact bytes, signature state and caller-supplied source metadata.
.DESCRIPTION
Run after signing, if used. OutputPath must be new. Signature presence/status is
reported, but this command does not replace explicit signature/trust verification.
.PARAMETER Artifact
Existing final artifact; hash and signature metadata are read from these bytes.
.PARAMETER OutputPath
New JSON file in an existing parent directory; existing files are never replaced.
.PARAMETER Version
Consumer-supplied version label; it is not inferred from the artifact.
.PARAMETER SourceCommit
Consumer-supplied source revision; this command does not consult Git.
.PARAMETER SourceDirty
Consumer's declaration that the source checkout had local changes.
.OUTPUTS
Object: Artifact, Manifest and SHA256. Diagnostics are not pipeline data.
.EXAMPLE
./common/write-artifact-manifest.ps1 -Artifact C:/build/app.msi -OutputPath C:/build/release.json -Version 1.2.3 -SourceCommit YOUR_SOURCE_COMMIT
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact,[Parameter(Mandatory)][string]$OutputPath,[string]$Version,[string]$SourceCommit,[switch]$SourceDirty)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Artifacts.ps1')
# Keep this wrapper thin so library callers and CLI callers share write semantics.
Write-WbtArtifactManifest @PSBoundParameters
