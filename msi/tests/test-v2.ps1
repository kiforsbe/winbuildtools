#requires -Version 7.4
<#
.SYNOPSIS
Exercise consumer-owned identities, scope and tamper rejection without installing.
.DESCRIPTION
Synthetic files and copied MSI mutations stay in one guarded temporary directory.
Both processor tables are inspected; only the native processor runs costing.
#>
$ErrorActionPreference='Stop'
$engine=Split-Path $PSScriptRoot -Parent
foreach($name in @('Configuration','Identity','Branding','Payload','Database','Registration','Maintenance','Scope','Presentation','Wizard','Semantics','Authoring','Inspection')) { if(Test-Path "$engine/$name.ps1") { . "$engine/$name.ps1" } }
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('WbtV2-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path "$fixture/payload/Assets" -Force
$script:checks=0
function Check([bool]$Value,[string]$Message) { if(!$Value) { throw $Message }; $script:checks++ }
try {
 foreach($name in @('Example.exe','Assets/Example.ico')) { [IO.File]::WriteAllText("$fixture/payload/$name",'Synthetic '+$name) }
 # Exercise the versioned-file branch using an installed framework binary as
 # inert fixture bytes; it is neither executed nor redistributed by the tests.
 Copy-Item -LiteralPath "$PSHOME/pwsh.dll" -Destination "$fixture/payload/versioned.dll"
 foreach($mode in @('machine','user','choice-user','choice-machine','ARM64','no-icon','machine-graceful')) {
  $config=Read-MsiConfiguration "$engine/example.json"
  $config.schemaVersion=2; $config.architecture=if($mode -eq 'ARM64') {'ARM64'}else{'x64'}
  $config.product.productCode=[guid]::NewGuid().ToString('B').ToUpperInvariant()
  $config.product.upgradeCode=[guid]::NewGuid().ToString('B').ToUpperInvariant()
  $config.product.name="Fixture $mode"
  $config.components=@{'Example.exe'=[guid]::NewGuid().ToString('B').ToUpperInvariant();'Assets/Example.ico'=[guid]::NewGuid().ToString('B').ToUpperInvariant();'versioned.dll'=[guid]::NewGuid().ToString('B').ToUpperInvariant()}
  $config.payload.allowedExtensions+='.dll'
  $config.installation.directoryName="Install $mode"; $config.installation.menuDirectoryName="Menu $mode"
  $config.installation.restartManager=if($mode -eq 'machine-graceful') {'graceful'}else{'disabled'}
  $config.installation.scope=if($mode -like 'choice-*') {'choice'}elseif($mode -in @('ARM64','no-icon')) {'user'}elseif($mode -eq 'machine-graceful') {'machine'}else{$mode}
  if($mode -eq 'no-icon') { $config.application.Remove('icon') }
  if($config.installation.scope -eq 'choice') { $config.installation.defaultScope=$mode.Split('-')[1] }
  $config | ConvertTo-Json -Depth 10 | Set-Content "$fixture/config.json"
  $config=Read-MsiConfiguration "$fixture/config.json"
  $path="$fixture/$mode.msi"
  New-MsiPackage $config "$fixture/payload" $path '1.2.3' $config.architecture
  $info=Read-MsiPackage $path
  Check ($info.Properties.ProductCode -ceq $config.product.productCode) 'Literal product GUID.'
  Check ($info.Properties.UpgradeCode -ceq $config.product.upgradeCode) 'Literal upgrade GUID.'
  Check ($info.Properties.MSIRESTARTMANAGERCONTROL -ceq $(if($mode -eq 'machine-graceful'){'0'}else{'Disable'})) 'Consumer selects RM policy.'
  Check ((@($info.Directories | Where-Object Directory -eq INSTALLFOLDER)[0].DefaultDir -split '\|')[-1] -ceq "Install $mode") 'Exact install directory.'
  Check ((@($info.Directories | Where-Object Directory -eq APPMENUDIR)[0].DefaultDir -split '\|')[-1] -ceq "Menu $mode") 'Independent menu directory.'
  Check ($info.WordCount -eq $(if($config.installation.scope -eq 'machine'){2}else{10})) 'Context privilege summary.'
  Check ($info.Properties.ALLUSERS -ceq $(if($config.installation.scope -eq 'machine'){'1'}else{'2'})) 'Native scope property.'
  Check ($info.Properties.MSIINSTALLPERUSER -ceq $(if($mode -in @('user','choice-user','ARM64','no-icon')){'1'}else{$null})) 'Native per-user default.'
  Check (@($info.Components | Where-Object ComponentId -notin $config.components.Values).Count -eq 0) 'Literal component GUIDs.'
  Assert-MsiContents $path "$fixture/payload" $config '1.2.3' $config.architecture "$fixture/inspection-$mode"
  $ui=Read-MsiMaintenanceUi $path
  if($config.installation.scope -eq 'choice') {
   Check (@($ui.InstallUi | Where-Object { $_.Action -ceq 'WbtWelcome' -and $_.Condition -ceq 'NOT Installed AND UILevel = 5' -and $_.Sequence -eq '5' }).Count -eq 1) 'Scope choice before discovery, skipped in maintenance.'
   Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq 'WbtScope' -and $_.Event -ceq '[MSIINSTALLPERUSER]' -and $_.Argument -ceq '{}' -and $_.Ordering -eq '3' }).Count -eq 1) 'All users explicitly clears per-user selection.'
  }
  if($mode -ne 'choice-user') { continue }
  # The actual reader processes copied databases. A preflight sentinel proves
  # that semantic rejection happens before any native costing or extraction.
  $originalPreflight=${function:Assert-MsiPreflight}
  function Assert-MsiPreflight { throw 'UNEXPECTED_PREFLIGHT' }
  try {
   $mutations=@(
    'UPDATE `Directory` SET `DefaultDir`=''WRONG'' WHERE `Directory`=''INSTALLFOLDER''',
    'UPDATE `Directory` SET `Directory_Parent`=''TARGETDIR'' WHERE `Directory`=''APPMENUDIR''',
    'UPDATE `Property` SET `Value`=''Wrong'' WHERE `Property`=''Manufacturer''',
    'UPDATE `Component` SET `Condition`=''0''',
    'UPDATE `File` SET `Version`=''9.9.9.9''',
    'UPDATE `MsiFileHash` SET `HashPart1`=123',
    'UPDATE `Upgrade` SET `ActionProperty`=''WRONG''',
    'UPDATE `RegLocator` SET `Name`=''Wrong''',
    'UPDATE `LaunchCondition` SET `Description`=''Wrong''',
    'UPDATE `Shortcut` SET `Arguments`=''wrong''',
    'UPDATE `InstallUISequence` SET `Sequence`=799 WHERE `Action`=''WbtWelcome''',
    'UPDATE `ControlEvent` SET `Ordering`=9 WHERE `Event`=''[ALLUSERS]'''
    'UPDATE `Directory` SET `DefaultDir`=''WRONG'' WHERE `Directory`=''APPMENUDIR''',
    'UPDATE `Directory` SET `DefaultDir`=''WRONG|Assets'' WHERE `Directory_Parent`=''INSTALLFOLDER''',
    'UPDATE `Property` SET `Value`=''Wrong'' WHERE `Property`=''ProductName''',
    'UPDATE `Property` SET `Value`=''1044'' WHERE `Property`=''ProductLanguage''',
    'UPDATE `Property` SET `Value`=''WRONG'' WHERE `Property`=''SecureCustomProperties''',
    'UPDATE `Property` SET `Value`=''1'' WHERE `Property`=''ALLUSERS''',
    'UPDATE `Component` SET `ComponentId`=''{99999999-0000-4000-8000-000000000001}''',
    'UPDATE `File` SET `Language`=''1044''',
    'UPDATE `File` SET `Attributes`=0',
    'DELETE FROM `MsiFileHash`',
    'summary-privilege','summary-author','upgrade-range','upgrade-attributes','launch-condition','scope-maintenance'
   )
   $index=0
   foreach($sql in $mutations) {
    $tampered="$fixture/mutated-$index.msi"; Copy-Item $path $tampered
    $installer=$null;$db=$null
    try {
     $installer=New-Object -ComObject WindowsInstaller.Installer; $db=$installer.OpenDatabase($tampered,1)
     switch($sql) {
      summary-privilege { $summary=$db.SummaryInformation(20); try { $summary.Property(15)=2; $null=$summary.Persist() } finally { Close-MsiCom $summary } }
      summary-author { $summary=$db.SummaryInformation(20); try { $summary.Property(4)='Wrong'; $null=$summary.Persist() } finally { Close-MsiCom $summary } }
      {$_ -in @('upgrade-range','upgrade-attributes')} {
       Invoke-MsiSql $db 'DELETE FROM `Upgrade`'
       Add-MsiRow $installer $db Upgrade @('UpgradeCode','VersionMax','Attributes','ActionProperty') @($config.product.upgradeCode,$(if($sql -eq 'upgrade-range'){'9.9.9'}else{'1.2.3'}),$(if($sql -eq 'upgrade-attributes'){1}else{0}),'OLDERVERSIONS')
       Add-MsiRow $installer $db Upgrade @('UpgradeCode','VersionMin','Attributes','ActionProperty') @($config.product.upgradeCode,'1.2.3',258,'NEWERVERSIONS')
      }
      launch-condition { Invoke-MsiSql $db 'DELETE FROM `LaunchCondition`'; Add-MsiRow $installer $db LaunchCondition @('Condition','Description') @('1','Wrong') }
      scope-maintenance { Invoke-MsiSql $db 'DELETE FROM `InstallUISequence` WHERE `Action`=''WbtWelcome'''; Add-MsiRow $installer $db InstallUISequence @('Action','Condition','Sequence') @('WbtWelcome','UILevel = 5',5) }
      default { Invoke-MsiSql $db $sql }
     }
     $null=$db.Commit()
    } finally { Close-MsiCom $db;Close-MsiCom $installer }
    $hash=(Get-FileHash $tampered).Hash; $failure=$null
    try { Assert-MsiContents $tampered "$fixture/payload" $config '1.2.3' x64 "$fixture/rejected-$index" } catch { $failure=$_ }
    Check ($failure -and "$failure" -notmatch 'UNEXPECTED_PREFLIGHT') "Mutation $index rejected before preflight."
    Check (!(Test-Path "$fixture/rejected-$index")) 'No extraction on semantic failure.'
    Check ((Get-FileHash $tampered).Hash -ceq $hash) 'Read-only mutation inspection.'
    $index++
   }
  } finally { ${function:Assert-MsiPreflight}=$originalPreflight }
 }
 Write-Host "V2 native checks passed: $checks"
} finally {
 $target=[IO.Path]::GetFullPath($fixture)
 if([IO.Path]::GetDirectoryName($target) -ne [IO.Path]::GetTempPath().TrimEnd('\') -or [IO.Path]::GetFileName($target) -notlike 'WbtV2-*') { throw 'Unsafe cleanup.' }
 Remove-Item -LiteralPath $target -Recurse -Force
}
