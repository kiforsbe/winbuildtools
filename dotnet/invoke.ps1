#requires -Version 7.4
<#
.SYNOPSIS
Runs an explicit .NET restore, build or publish with a shared isolated context.
.DESCRIPTION
Requires a caller-installed .NET 8+ SDK. Restore always uses locked mode; Build
and Publish always use --no-restore. Use identical project, properties, runtime
and artifacts paths in each operation. This command never selects dependencies,
creates a project lock, audits license rights or downloads the tooling repository.
Project-specific SDK selection/global.json, restore feeds and policies remain
consumer-owned. Do not supply secrets in properties or logged tool output.
.PARAMETER Properties
MSBuild property names and scalar values, identical across operations. Semicolons,
newlines and reserved context property overrides are rejected; arrays/items and
complex settings belong in consumer MSBuild files rather than command arguments.
.EXAMPLE
./dotnet/invoke.ps1 -Operation Restore -Project C:/app/App.csproj -ArtifactsDirectory C:/build/intermediate
.EXAMPLE
./dotnet/invoke.ps1 -Operation Publish -Project C:/app/App.csproj -ArtifactsDirectory C:/build/intermediate -OutputDirectory C:/build/payload
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Restore','Build','Publish')][string]$Operation,
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$ArtifactsDirectory,
    [string]$OutputDirectory,
    [ValidateSet('Debug','Release')][string]$Configuration='Release',
    [string]$RuntimeIdentifier,
    [hashtable]$Properties=@{},
    [string]$NuGetConfig,
    [string]$DotnetPath='dotnet',
    [string]$LogPath
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../common/Tools.ps1')
$projectPath=Resolve-WbtPath $Project
if(!(Test-Path -LiteralPath $projectPath -PathType Leaf)) { throw 'Project does not exist.' }
Assert-WbtNoLinks $projectPath
$artifacts=Resolve-WbtPath $ArtifactsDirectory
Assert-WbtNoLinks $artifacts
if($OutputDirectory -and $Operation -ne 'Publish') { throw 'OutputDirectory is only valid for Publish.' }
if($RuntimeIdentifier -and $RuntimeIdentifier -notmatch '^[A-Za-z0-9.-]+$') { throw 'Invalid runtime identifier.' }
if($OutputDirectory) {
    $output=Resolve-WbtPath $OutputDirectory
    Assert-WbtNoLinks $output
    # Avoid publishing over source or intermediate build state.
    Assert-WbtOutsideTree $projectPath $output
    Assert-WbtOutsideTree $artifacts $output
    Assert-WbtOutsideTree $output $artifacts
    if(Test-Path -LiteralPath $output) { throw 'Publish output must be new.' }
}
$propertyArgs=[Collections.Generic.List[string]]::new()
foreach($name in $Properties.Keys | Sort-Object) {
    if($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or [string]$Properties[$name] -match '[;,\r\n]' -or $Properties[$name] -is [array]) { throw "Invalid MSBuild property: $name" }
    if($name -in @('ArtifactsPath','UseArtifactsOutput','Configuration','RuntimeIdentifier','OutputPath','BaseOutputPath','BaseIntermediateOutputPath','IntermediateOutputPath','PublishDir','RestoreLockedMode')) { throw "Context-owned property must use the helper parameters: $name" }
    $propertyArgs.Add("-p:$name=$($Properties[$name])")
}
if($NuGetConfig) { $NuGetConfig=Resolve-WbtPath $NuGetConfig; if(!(Test-Path -LiteralPath $NuGetConfig -PathType Leaf)) { throw 'NuGet configuration does not exist.' } }
if(!$LogPath) { $LogPath=Join-Path $artifacts ("logs/$($Operation.ToLowerInvariant())-"+[guid]::NewGuid().ToString('N')+'.log') }
$LogPath=Resolve-WbtPath $LogPath
$arguments=@($Operation.ToLowerInvariant(),$projectPath,'--artifacts-path',$artifacts,'--nologo',"-p:Configuration=$Configuration")+@($propertyArgs)
if($RuntimeIdentifier) { $arguments+=@('--runtime',$RuntimeIdentifier) }
if($Operation -eq 'Restore') {
    $arguments+='--locked-mode'
    if($NuGetConfig) { $arguments+=@('--configfile',$NuGetConfig) }
} else {
    $arguments+='--no-restore'
    if($OutputDirectory) { $arguments+=@('--output',$output) }
}
Push-Location (Split-Path $projectPath -Parent)
try { Invoke-WbtTool $DotnetPath $arguments $LogPath } finally { Pop-Location }
[pscustomobject]@{Operation=$Operation;Project=$projectPath;ArtifactsDirectory=$artifacts;OutputDirectory=$output;LogPath=(Resolve-WbtPath $LogPath)}
