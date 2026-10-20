#requires -Version 7.4
<#
.SYNOPSIS
Runs non-installing winbuildtools verification.
.DESCRIPTION
Default tests require Windows and the Windows SDK. -Integration also requires
Git and a stable installed .NET 8+ SDK, exercises a managed fixture and clones a
disposable consumer with a pinned submodule. No product/certificate is installed.
.EXAMPLE
./verify.ps1 -Integration
#>
[CmdletBinding()]
param([switch]$Integration)
$ErrorActionPreference='Stop'
if(!$IsWindows) { throw 'Windows is required for native MSI/MSIX verification.' }
foreach($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File -Recurse | Where-Object { $_.FullName -notmatch '[\\/](artifacts|work|\.git)[\\/]' }) {
    $tokens=$null; $errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors) { throw "PowerShell syntax error: $($file.FullName): $errors" }
}
foreach($test in @('msi/tests/test-config.ps1','msi/tests/test-msi.ps1','tests/test-common.ps1','tests/test-msix.ps1','tests/test-signing.ps1','tests/test-dotnet.ps1','tests/test-repository.ps1')) {
    & (Join-Path $PSScriptRoot $test)
    if(!$?) { throw "Verification failed: $test" }
}
if($Integration) {
    & (Join-Path $PSScriptRoot 'tests/test-dotnet.ps1') -Integration
    & (Join-Path $PSScriptRoot 'tests/test-consumer.ps1')
}
Write-Host 'winbuildtools verification passed.'
