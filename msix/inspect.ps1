#requires -Version 7.4
<#
.SYNOPSIS
Inspects an existing MSIX against its expected payload and manifest.
.DESCRIPTION
Works with packages produced by this tool or another build system. Output must
be new. Verifies identity, manifest content and exact payload bytes; does not
install a package or establish its signature trust or application correctness.
.EXAMPLE
./msix/inspect.ps1 -Artifact C:/build/app.msix -PayloadDirectory C:/build/payload -Manifest C:/product/AppxManifest.xml -OutputDirectory C:/build/new-inspection
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact,[Parameter(Mandatory)][string]$PayloadDirectory,[Parameter(Mandatory)][string]$Manifest,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Msix.ps1')
Test-WbtMsix $Artifact $PayloadDirectory $Manifest $OutputDirectory
