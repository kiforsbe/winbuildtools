#requires -Version 7.4
<#
.SYNOPSIS
Records final artifact bytes, signature state and caller-supplied source metadata.
.DESCRIPTION
Run after signing, if used. OutputPath must be new. Signature presence/status is
reported, but this command does not replace explicit signature/trust verification.
.EXAMPLE
./common/write-artifact-manifest.ps1 -Artifact C:/build/app.msi -OutputPath C:/build/release.json -Version 1.2.3 -SourceCommit YOUR_SOURCE_COMMIT
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact,[Parameter(Mandatory)][string]$OutputPath,[string]$Version,[string]$SourceCommit,[switch]$SourceDirty)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Artifacts.ps1')
Write-WbtArtifactManifest @PSBoundParameters
