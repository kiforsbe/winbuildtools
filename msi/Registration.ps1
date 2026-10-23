#requires -Version 7.4
<#
.SYNOPSIS
Native MSI product-location and Start-menu uninstall registration.
.DESCRIPTION
Only three exact declarative type51 property setters are permitted. They restore
context-specific folder memory before costing and format the costed ARP location.
They run no program/script and are not installation transactions. One native
Registry row, owned by the executable component, remembers the resolved folder.
Shortcut properties use Installer5.0's native property-store authoring. Persistent
application identity, when supplied, belongs to the consumer and is never guessed.
#>
function Get-MsiRegistrationActions {
 ,@('WbtSetInstallLocation',51,'ARPINSTALLLOCATION','[INSTALLFOLDER]')
 ,@('WbtUseUserInstallLocation',51,'INSTALLFOLDER','[WBTPREVUSERPATH]')
 ,@('WbtUseMachineInstallLocation',51,'INSTALLFOLDER','[WBTPREVMACHINEPATH]')
}
function Get-MsiRegistrationDefinition($Configuration,[string]$Architecture,[object[]]$Files) {
 $properties=[Collections.Generic.List[object]]::new()
 for($index=1;$index -le $Configuration.shortcuts.Count;$index++) {
  $properties.Add(@("WbtUninstall$index","Shortcut$index",'System.AppUserModel.UninstallCommand','"[System64Folder]msiexec.exe" /x [ProductCode]'))
  if($Configuration.application.appUserModelId) { $properties.Add(@("WbtAppId$index","Shortcut$index",'System.AppUserModel.ID',$Configuration.application.appUserModelId)) }
 }
 $main=@($Files | Where-Object Relative -EQ $Configuration.application.executable.Replace('\','/'))[0]
 $key='Software\winbuildtools\Installations\'+(Get-MsiPackageGuid $Configuration $Architecture upgrade)
 @{
  CustomAction=@{Columns=@('Action','Type','Source','Target');Rows=@(Get-MsiRegistrationActions)}
  MsiShortcutProperty=@{Columns=@('MsiShortcutProperty','Shortcut_','PropertyKey','PropVariantValue');Rows=$properties.ToArray()}
  Registry=@{Columns=@('Registry','Root','Key','Name','Value','Component_');Rows=@(,@('WbtRememberInstallFolder',-1,$key,'InstallLocation','[INSTALLFOLDER]',$main.Component))}
  AppSearch=@{Columns=@('Property','Signature_');Rows=@(@('WBTPREVUSERPATH','WbtUserInstallFolder'),@('WBTPREVMACHINEPATH','WbtMachineInstallFolder'))}
  RegLocator=@{Columns=@('Signature_','Root','Key','Name','Type');Rows=@(@('WbtUserInstallFolder',1,$key,'InstallLocation',18),@('WbtMachineInstallFolder',2,$key,'InstallLocation',18))}
 }
}
function Get-MsiRegistrationSequences {
 ,@('WbtUseUserInstallLocation','(Installed OR OLDERVERSIONS) AND (NOT ALLUSERS OR (ALLUSERS = 2 AND MSIINSTALLPERUSER = 1)) AND WBTPREVUSERPATH',750)
 ,@('WbtUseMachineInstallLocation','(Installed OR OLDERVERSIONS) AND (ALLUSERS = 1 OR (ALLUSERS = 2 AND NOT MSIINSTALLPERUSER)) AND WBTPREVMACHINEPATH',751)
 ,@('WbtSetInstallLocation','NOT REMOVE~="ALL"',1125)
}
function Add-MsiRegistration($Installer,$Database,$Configuration,[string]$Architecture,[object[]]$Files) {
 Invoke-MsiSql $Database 'CREATE TABLE `CustomAction` (`Action` CHAR(72) NOT NULL, `Type` SHORT NOT NULL, `Source` CHAR(72), `Target` CHAR(255) PRIMARY KEY `Action`)'
 Invoke-MsiSql $Database 'CREATE TABLE `MsiShortcutProperty` (`MsiShortcutProperty` CHAR(72) NOT NULL, `Shortcut_` CHAR(72) NOT NULL, `PropertyKey` CHAR(255) NOT NULL, `PropVariantValue` CHAR(255) NOT NULL PRIMARY KEY `MsiShortcutProperty`)'
 Invoke-MsiSql $Database 'CREATE TABLE `Registry` (`Registry` CHAR(72) NOT NULL, `Root` SHORT NOT NULL, `Key` CHAR(255) NOT NULL, `Name` CHAR(255), `Value` CHAR(0) LOCALIZABLE, `Component_` CHAR(72) NOT NULL PRIMARY KEY `Registry`)'
 foreach($entry in (Get-MsiRegistrationDefinition $Configuration $Architecture $Files).GetEnumerator()) {
  foreach($row in $entry.Value.Rows) { Add-MsiRow $Installer $Database $entry.Key $entry.Value.Columns $row }
 }
 foreach($table in @('InstallUISequence','InstallExecuteSequence')) {
  # CostFinalize establishes the real user/machine directory before native ARP
  # registration. Do this in both sequences so /qn needs no UI side effects.
  foreach($row in @(Get-MsiRegistrationSequences)) { Add-MsiRow $Installer $Database $table @('Action','Condition','Sequence') $row }
 }
 Add-MsiRow $Installer $Database InstallExecuteSequence @('Action','Sequence') @('WriteRegistryValues',5000)
 Add-MsiRow $Installer $Database InstallExecuteSequence @('Action','Sequence') @('RemoveRegistryValues',2600)
}
function Assert-MsiCustomActionPolicy($Database) {
 # This exact allowlist is checked even by copy-only preflight before OpenPackage.
 # Never generalize to "all type51"; consumer-controlled property setters could
 # change target folders, execution context or shutdown policy before validation.
 $columns=@('Action','Type','Source','Target')
 $rows=@(Get-MsiRows $Database CustomAction $columns)
 Assert-MsiRowsMatch 'custom-action allowlist' $rows $columns @(Get-MsiRegistrationActions)
}
