#requires -Version 7.4

<#
.SYNOPSIS
Small assertion and disposable-directory helpers for repository tests.
.DESCRIPTION
Dot-source from tests; no external test framework is required. Fixtures are direct
children of the system temp directory with an owned prefix. New-TestDirectory
only chooses a path; each test creates the directories it needs.
#>
$ErrorActionPreference='Stop'
function Check([bool]$Value,[string]$Message) { if(!$Value) { throw $Message } }
function Rejected([scriptblock]$Action,[string]$Pattern='.') {
    # Catch only the action under test. Keeping the assertions outside the catch
    # prevents an assertion failure from being mistaken for an expected rejection.
    $failure=$null
    try { & $Action | Out-Null } catch { $failure=$_ }
    Check ($null -ne $failure) 'Expected rejection.'
    Check ($failure.ToString() -match $Pattern) "Unexpected rejection: $failure"
}
function New-TestDirectory { Join-Path ([IO.Path]::GetTempPath()) ('Winbuildtools-'+[guid]::NewGuid().ToString('N')) }
function Remove-TestDirectory([string]$Path) {
    # Validate the absolute parent and owned prefix immediately before recursive
    # deletion; never allow callers to turn cleanup into a general directory wipe.
    $target=[IO.Path]::GetFullPath($Path)
    if([IO.Path]::GetDirectoryName($target) -ne [IO.Path]::GetTempPath().TrimEnd('\') -or [IO.Path]::GetFileName($target) -notlike 'Winbuildtools-*') { throw 'Unsafe test cleanup.' }
    if(Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
}
