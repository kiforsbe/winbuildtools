#requires -Version 7.4
$ErrorActionPreference='Stop'
function Check([bool]$Value,[string]$Message) { if(!$Value) { throw $Message } }
function Rejected([scriptblock]$Action,[string]$Pattern='.') {
    $failure=$null
    try { & $Action | Out-Null } catch { $failure=$_ }
    Check ($null -ne $failure) 'Expected rejection.'
    Check ($failure.ToString() -match $Pattern) "Unexpected rejection: $failure"
}
function New-TestDirectory { Join-Path ([IO.Path]::GetTempPath()) ('Winbuildtools-'+[guid]::NewGuid().ToString('N')) }
function Remove-TestDirectory([string]$Path) {
    $target=[IO.Path]::GetFullPath($Path)
    if([IO.Path]::GetDirectoryName($target) -ne [IO.Path]::GetTempPath().TrimEnd('\') -or [IO.Path]::GetFileName($target) -notlike 'Winbuildtools-*') { throw 'Unsafe test cleanup.' }
    if(Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
}
