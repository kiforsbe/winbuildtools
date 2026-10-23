#requires -Version 7.4

<#
.SYNOPSIS
Builds and inspects an unsigned Windows Installer package.
.DESCRIPTION
Consumes an existing payload; never builds the application, installs a product,
changes certificate trust or reads a repository. Signing belongs to the caller,
which must then recompute the artifact hash.
.PARAMETER Config
JSON conforming to config.schema.json or config-v2.schema.json; asset paths are
relative to payload. Optional ui fields control destination editing/license text.
.PARAMETER PayloadDirectory
Published application directory with no links/reparse points.
.PARAMETER Version
Stable major.minor.patch version, maximum 255.255.65534.
.PARAMETER Architecture
x64 or ARM64; determines native MSI metadata and identity namespace.
.PARAMETER OutputDirectory
New directory outside payload. Existing directories are never overwritten.
.OUTPUTS
Object: Artifact, Version, Architecture, SHA256 and InspectionReport.
.EXAMPLE
./package.ps1 -Config ./example.json -PayloadDirectory C:/build/app -Version 1.0.0 -Architecture x64 -OutputDirectory C:/build/msi-new
#>

[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$Config,
 [Parameter(Mandatory)][string]$PayloadDirectory,
 [Parameter(Mandatory)][string]$Version,
 [Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Architecture,
 [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
# Load the standalone engine in dependency order; importing ../common here would
# break the supported copy-only-msi deployment and its standalone regression test.
foreach($name in @('Configuration','Identity','Payload','Database','Registration','Maintenance','Scope','Wizard','Semantics','Authoring','Inspection')) { . (Join-Path $PSScriptRoot "$name.ps1") }
$configuration=Read-MsiConfiguration (Resolve-MsiPath $Config)
Assert-MsiVersion $Version
$payload=Resolve-MsiPath $PayloadDirectory
$output=Resolve-MsiPath $OutputDirectory
# Validate the entire input set before creating output. Lower-level authoring
# repeats payload validation so direct library callers receive the same checks.
$null=Get-MsiPayload $configuration $payload $Architecture
if($output.TrimEnd('\') -eq $payload.TrimEnd('\') -or $output.StartsWith($payload.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Output must be outside the payload tree.' }
if(Test-Path -LiteralPath $output) { throw 'OutputDirectory must be new; previous artifacts are never overwritten.' }
$null=New-Item -ItemType Directory -Path $output
$artifact=Join-Path $output "$($configuration.product.id)-$Version-$($Architecture.ToLowerInvariant()).msi"
# No success object/report is emitted until tables AND embedded bytes pass.
# An inspection failure retains output for diagnosis; retry with a new directory.
New-MsiPackage $configuration $payload $artifact $Version $Architecture
Assert-MsiContents $artifact $payload $configuration $Version $Architecture (Join-Path $output 'inspection')
$hash=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
$report=Join-Path $output 'inspection.json'
$result=[pscustomobject]@{Artifact=$artifact;Version=$Version;Architecture=$Architecture;SHA256=$hash;InspectionReport=$report}
$result | ConvertTo-Json | Set-Content -LiteralPath $report -Encoding utf8NoBOM
$result
