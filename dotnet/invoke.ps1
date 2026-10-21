#requires -Version 7.4

<#
.SYNOPSIS
Runs an explicit .NET restore, build or publish with a shared isolated context.
.DESCRIPTION
Requires a caller-installed .NET 8+ SDK. Restore always uses locked mode; Build
and Publish always use --no-restore. Use identical project, properties, runtime
and artifacts paths in each operation. This command never selects dependencies,
creates a project lock, audits license rights or downloads the tooling repository.
Requires an existing project lock file; custom NuGetLockFilePath can be supplied
through Properties. Consumers must also commit locks for referenced projects.
Project-specific SDK selection/global.json, restore feeds and policies remain
consumer-owned. Do not supply secrets in properties or logged tool output.
.PARAMETER Properties
MSBuild property names and scalar values, identical across operations. Semicolons,
newlines and reserved context property overrides are rejected; arrays/items and
complex settings belong in consumer MSBuild files rather than command arguments.
.PARAMETER Operation
One explicit Restore, Build or Publish step; no implicit multi-step pipeline.
.PARAMETER Project
Single existing csproj/fsproj/vbproj. Its directory controls SDK/global.json lookup.
.PARAMETER ArtifactsDirectory
Shared artifacts root, identical for restore/build/publish of the same context.
.PARAMETER OutputDirectory
New publish destination. Valid only for Publish and separate from build artifacts.
.PARAMETER Configuration
Debug or Release, default Release; keep identical across operations.
.PARAMETER RuntimeIdentifier
Optional runtime identifier, also part of the shared restore/build context.
.PARAMETER NuGetConfig
Optional restore configuration; only forwarded to the Restore invocation.
.PARAMETER DotnetPath
Installed dotnet executable, default dotnet resolved from the command search path.
.PARAMETER LogPath
Optional caller-relative log path; defaults to a unique file under artifacts/logs.
.OUTPUTS
Object: Operation, Project, ArtifactsDirectory, OutputDirectory and LogPath.
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
if([IO.Path]::GetExtension($projectPath) -notin @('.csproj','.fsproj','.vbproj')) { throw 'Select a single .NET project file, not a solution.' }
Assert-WbtNoLinks $projectPath
$output=$null
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
# MSBuild parses separators within a single -p argument. Reject list/injection
# syntax and context overrides even though native arguments are passed as an array.
$propertyArgs=[Collections.Generic.List[string]]::new()
foreach($name in $Properties.Keys | Sort-Object) {
    if($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or [string]$Properties[$name] -match '[;,\r\n]' -or $Properties[$name] -is [array]) { throw "Invalid MSBuild property: $name" }
    if($name -in @('ArtifactsPath','UseArtifactsOutput','Configuration','RuntimeIdentifier','OutputPath','BaseOutputPath','BaseIntermediateOutputPath','IntermediateOutputPath','PublishDir','RestoreLockedMode','RestorePackagesWithLockFile')) { throw "Context-owned property must use the helper parameters: $name" }
    $propertyArgs.Add("-p:$name=$($Properties[$name])")
}
if($NuGetConfig) { $NuGetConfig=Resolve-WbtPath $NuGetConfig; if(!(Test-Path -LiteralPath $NuGetConfig -PathType Leaf)) { throw 'NuGet configuration does not exist.' } }
if($Operation -eq 'Restore') {
    # NuGet's --locked-mode alone can restore without a lock. Refuse that gap
    # before invoking the SDK. Imported project settings remain caller-owned;
    # expose custom lock paths explicitly in Properties so this check can agree.
    $lockPath=if($Properties.ContainsKey('NuGetLockFilePath')) { [string]$Properties['NuGetLockFilePath'] } else { 'packages.lock.json' }
    if(![IO.Path]::IsPathRooted($lockPath)) { $lockPath=Join-Path (Split-Path $projectPath -Parent) $lockPath }
    $lockPath=Resolve-WbtPath $lockPath
    Assert-WbtNoLinks $lockPath
    if(!(Test-Path -LiteralPath $lockPath -PathType Leaf)) { throw "Existing project lock file required before restore: $lockPath" }
}
if(!$LogPath) { $LogPath=Join-Path $artifacts ("logs/$($Operation.ToLowerInvariant())-"+[guid]::NewGuid().ToString('N')+'.log') }
$LogPath=Resolve-WbtPath $LogPath
# Keep the entire context in every invocation. A build must consume the assets
# created by its explicit restore; --no-restore prevents silently changing them.
$arguments=@($Operation.ToLowerInvariant(),$projectPath,'--artifacts-path',$artifacts,'--nologo',"-p:Configuration=$Configuration",'-p:RestorePackagesWithLockFile=true')+@($propertyArgs)
if($RuntimeIdentifier) { $arguments+=@('--runtime',$RuntimeIdentifier) }
if($Operation -eq 'Restore') {
    $arguments+='--locked-mode'
    if($NuGetConfig) { $arguments+=@('--configfile',$NuGetConfig) }
} else {
    $arguments+='--no-restore'
    if($OutputDirectory) { $arguments+=@('--output',$output) }
}
# Resolve caller-relative paths before changing location. Run in the project
# directory for SDK selection and always restore the caller's PowerShell location.
Push-Location (Split-Path $projectPath -Parent)
try { Invoke-WbtTool $DotnetPath $arguments $LogPath } finally { Pop-Location }
[pscustomobject]@{Operation=$Operation;Project=$projectPath;ArtifactsDirectory=$artifacts;OutputDirectory=$output;LogPath=(Resolve-WbtPath $LogPath)}
