#requires -Version 7.4

<#
.SYNOPSIS
Creates and inspects an unsigned MSIX from prepared product inputs.
.DESCRIPTION
Copies the payload and caller-owned manifest into a new output tree. Does not
modify product identities, build applications, sign packages or import trust.
.PARAMETER PayloadDirectory
Prepared files without AppxManifest.xml or reserved MSIX container metadata.
.PARAMETER Manifest
Caller-owned AppxManifest.xml supplied separately from the payload directory.
.PARAMETER OutputDirectory
New tree outside the payload, holding staging, artifact, logs and inspection.
.OUTPUTS
Object: Artifact, Name, Publisher, Version, Architecture, SHA256, InspectionDirectory.
.EXAMPLE
./msix/package.ps1 -PayloadDirectory C:/build/app -Manifest C:/product/AppxManifest.xml -OutputDirectory C:/build/new-msix
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PayloadDirectory,[Parameter(Mandatory)][string]$Manifest,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Msix.ps1')
# Packaging and inspection share one implementation; preserve its result contract.
New-WbtMsix $PayloadDirectory $Manifest $OutputDirectory
