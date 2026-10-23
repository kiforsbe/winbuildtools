#requires -Version 7.4

<#
.SYNOPSIS
Low-level MSI identity scoping, tool execution and database/COM helpers.
.DESCRIPTION
Requires Identity.ps1. Table/column identifiers come from engine code; caller
values go through records. Suppress COM return values so only intended results
reach PowerShell's success stream. Each acquired COM reference must be released.
#>
function Get-MsiPackageGuid($Configuration,[string]$Architecture,[string]$Scope) {
 if($Configuration.schemaVersion -eq 2) {
  if($Architecture -ine $Configuration.architecture) { throw 'Configuration architecture mismatch.' }
  if($Scope -eq 'upgrade') { return $Configuration.product.upgradeCode }
  if($Scope -match '^product/') { return $Configuration.product.productCode }
  if($Scope -match '^component/(.+)$' -and $Configuration.components.ContainsKey($Matches[1].Replace('\','/'))) { return $Configuration.components[$Matches[1].Replace('\','/')] }
  throw "Unsupported or missing configured identity scope: $Scope"
 }
 # Architecture is part of every package identity scope, including upgrade family.
 return Get-MsiGuid $Configuration.product.upgradeCode "$Architecture/$Scope"
}
function Get-MsiPackageId($Configuration,[string]$Architecture,[string]$Prefix,[string]$Scope) {
 # Internal identifiers remain deterministic generic names in both versions;
 # v2 persistent GUID columns are separately supplied by the consumer.
 return Get-MsiId $Prefix $Configuration.product.upgradeCode "$Architecture/$Scope"
}
function Invoke-MsiTool([string]$Tool,[string[]]$Arguments) {
 # Standalone engine runner: retain child diagnostics in the exception on failure
 # without taking a dependency on the repository's common logging implementation.
 $messages=@(& $Tool @Arguments 2>&1)
 if($LASTEXITCODE -ne 0) { throw "$([IO.Path]::GetFileName($Tool)) failed: $($messages -join [Environment]::NewLine)" }
 Write-Host "$([IO.Path]::GetFileName($Tool)): succeeded"
}
function Close-MsiCom($Object) {
 # Call only for references owned by this engine; FinalRelease invalidates aliases.
 if($null -ne $Object -and [Runtime.InteropServices.Marshal]::IsComObject($Object)) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Object) }
}
function Invoke-MsiSql($Database,[string]$Sql) {
 # For engine-authored schema/action SQL. Configuration data belongs in Add-MsiRow.
 $view=$null
 try { $view=$Database.OpenView($Sql); $null=$view.Execute() } finally { if($view) { $null=$view.Close(); Close-MsiCom $view } }
}
# Use parameterized records for all values, including localized names and streams;
# callers never interpolate configuration values into SQL statements.
function Add-MsiRow($Installer,$Database,[string]$Table,[string[]]$Columns,[object[]]$Values,[int[]]$Streams=@()) {
 if($Table -notmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or @($Columns | Where-Object { $_ -notmatch '^[A-Za-z_][A-Za-z0-9_]*$' }).Count -or $Columns.Count -ne $Values.Count) { throw "Invalid MSI authoring row: $Table ($($Columns.Count) columns, $($Values.Count) values)." }
 $names=($Columns | ForEach-Object { '`'+$_+'`' }) -join ','
 $parameters=(@('?')*$Values.Count) -join ','
 $view=$null; $record=$null
 try {
  $view=$Database.OpenView(('INSERT INTO `{0}` ({1}) VALUES ({2})' -f $Table,$names,$parameters))
  $record=$Installer.CreateRecord($Values.Count)
  # Streams uses zero-based indexes into Values, while COM fields are one-based.
  # Null fields remain unset; binary streams must use SetStream, not StringData.
  for($i=0;$i -lt $Values.Count;$i++) {
   if($null -eq $Values[$i]) { continue }
   if($i -in $Streams) { $null=$record.SetStream($i+1,[string]$Values[$i]) }
   elseif($Values[$i] -is [int] -or $Values[$i] -is [long]) { $record.IntegerData($i+1)=[int]$Values[$i] }
   else { $record.StringData($i+1)=[string]$Values[$i] }
  }
  $null=$view.Execute($record)
 } finally { Close-MsiCom $record; if($view) { $null=$view.Close();Close-MsiCom $view } }
}
# Bound reads protect inspection from unexpectedly large/malformed tables.
function Get-MsiRows($Database,[string]$Table,[string[]]$Columns) {
 $view=$null
 try {
  $names=($Columns | ForEach-Object { '`'+$_+'`' }) -join ','
  $view=$Database.OpenView(('SELECT {0} FROM `{1}`' -f $names,$Table));$null=$view.Execute()
  $count=0
  while($record=$view.Fetch()) {
   try {
    if(++$count -gt 10000) { throw 'MSI inspection row limit exceeded.' }
    $row=[ordered]@{}
    for($i=0;$i -lt $Columns.Count;$i++) { $row[$Columns[$i]]=$record.StringData($i+1) }
    [pscustomobject]$row
   } finally { Close-MsiCom $record }
  }
 } finally { if($view) { $null=$view.Close();Close-MsiCom $view } }
}
