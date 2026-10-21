#requires -Version 7.4

<#
.SYNOPSIS
Inspects an existing MSIX against its expected payload and manifest.
.DESCRIPTION
Works with packages produced by this tool or another build system. Output must
be new. Verifies identity, manifest content and exact payload bytes; does not
install a package or establish its signature trust or application correctness.
.PARAMETER Artifact
Existing MSIX to unpack; package bytes are not modified.
.PARAMETER PayloadDirectory
Expected files to compare by relative name and hash, without container metadata.
.PARAMETER Manifest
Expected authoritative manifest, compared by identity and canonical XML.
.PARAMETER OutputDirectory
New inspection tree outside the expected payload, retaining unpacked files/logs.
.OUTPUTS
Object: Artifact, Name, Publisher, Version, Architecture, SHA256, InspectionDirectory.
.EXAMPLE
./msix/inspect.ps1 -Artifact C:/build/app.msix -PayloadDirectory C:/build/payload -Manifest C:/product/AppxManifest.xml -OutputDirectory C:/build/new-inspection
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact,[Parameter(Mandatory)][string]$PayloadDirectory,[Parameter(Mandatory)][string]$Manifest,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Msix.ps1')
# Use the same gate as package.ps1, including rejection of extra package files.
Test-WbtMsix $Artifact $PayloadDirectory $Manifest $OutputDirectory
