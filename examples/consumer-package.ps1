#requires -Version 7.4

<#
.SYNOPSIS
Example consumer adapter for a pinned external winbuildtools checkout.
.DESCRIPTION
Copy this script to the application repository root and maintain your product
JSON at deployment/msi.json. Publish/approve the application's payload first.
The script resolves the tool and JSON from its own location, independent of the
shell directory. Never downloads tools or changes the pinned submodule commit.
.OUTPUTS
The MSI command's result: Artifact, Version, Architecture, SHA256, InspectionReport.
.EXAMPLE
./package.ps1 -PayloadDirectory C:/build/payload -Version 1.2.3 -Architecture x64 -OutputDirectory C:/build/new-msi
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PayloadDirectory,[Parameter(Mandatory)][string]$Version,[Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Architecture,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
# Product/tool paths follow the adapter; payload/output paths retain the caller's
# working-directory semantics. Missing checkout is an error, never a fetch step.
$tool=Join-Path $PSScriptRoot 'external/winbuildtools/msi/package.ps1'
if(!(Test-Path -LiteralPath $tool -PathType Leaf)) { throw 'winbuildtools checkout is missing. Run: git submodule update --init --recursive' }
$config=Join-Path $PSScriptRoot 'deployment/msi.json'
if(!(Test-Path -LiteralPath $config -PathType Leaf)) { throw 'Consumer product configuration deployment/msi.json is missing.' }
& $tool -Config $config -PayloadDirectory $PayloadDirectory -Version $Version -Architecture $Architecture -OutputDirectory $OutputDirectory
