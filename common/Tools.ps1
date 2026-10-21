#requires -Version 7.4

<#
.SYNOPSIS
Native tool invocation and installed Windows SDK tool discovery.
.DESCRIPTION
Dot-source to load Paths.ps1 and these helpers. Diagnostics go to the host/log;
successful child output is not returned as pipeline data. No tool is downloaded.
#>
. (Join-Path $PSScriptRoot 'Paths.ps1')
function Invoke-WbtTool {
    param([string]$Tool,[string[]]$Arguments,[string]$LogPath)
    # Output only, never the argument list. Callers must not pass secret-bearing
    # commands here: even a child's diagnostics may echo its sensitive arguments.
    if(!(Get-Command $Tool -CommandType Application -ErrorAction SilentlyContinue)) { throw "Tool not found: $Tool" }
    # Inspect the exit code ourselves so nonzero exits still retain diagnostics
    # when a caller has enabled native-command errors with Stop semantics.
    $PSNativeCommandUseErrorActionPreference=$false
    $messages=@(& $Tool @Arguments 2>&1)
    $exitCode=$LASTEXITCODE
    if($LogPath) {
        $log=Resolve-WbtPath $LogPath
        $null=New-Item -ItemType Directory -Path (Split-Path $log -Parent) -Force
        $messages | Out-String | Add-Content -LiteralPath $log -Encoding utf8
    }
    if($exitCode -ne 0) {
        $messages | Select-Object -Last 12 | Out-Host
        throw "$([IO.Path]::GetFileName($Tool)) failed (exit $exitCode). Log: $LogPath"
    }
    Write-Host "$([IO.Path]::GetFileName($Tool)): succeeded"
}
function Get-WbtSdkTool {
    # Select the newest installed version meeting the interface floor. This is
    # discovery, not a check that the SDK is the latest supported upstream SDK.
    param([ValidateSet('makeappx.exe','signtool.exe')][string]$Name,[string]$SdkRoot)
    if(!$SdkRoot) { $SdkRoot=Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin' }
    if(!(Test-Path -LiteralPath $SdkRoot -PathType Container)) { throw "Windows SDK directory not found: $SdkRoot" }
    # Use a host-native tool when installed, with x64 emulation as an ARM64
    # fallback. Tool architecture does not constrain target package architecture.
    $hostArch=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    $architectures=if($hostArch -eq 'arm64') { @('arm64','x64') } else { @('x64') }
    foreach($dir in Get-ChildItem -LiteralPath $SdkRoot -Directory | Where-Object { $_.Name -match '^10\.0\.\d+\.\d+$' -and [version]$_.Name -ge [version]'10.0.26100.0' } | Sort-Object { [version]$_.Name } -Descending) {
        foreach($arch in $architectures) {
            $candidate=Join-Path $dir.FullName "$arch/$Name"
            if(Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    throw "Windows SDK 10.0.26100.0 or later with $Name is required."
}
