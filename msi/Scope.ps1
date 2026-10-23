#requires -Version 7.4
<#
.SYNOPSIS
Author native installation-context selection before discovery and costing.
.DESCRIPTION
V1 retains machine context. V2 fixed modes have no chooser; choice uses only
standard MSI controls/events. Silent installs use standard command-line properties.
No property rewrite or chooser runs for maintenance of an installed product.
#>
function Get-MsiScopeProperties($Configuration) {
 $result=@{ALLUSERS='1'}
 if($Configuration.schemaVersion -eq 2 -and $Configuration.installation.scope -ne 'machine') {
  $result.ALLUSERS='2'
  $default=if($Configuration.installation.scope -eq 'choice') {$Configuration.installation.defaultScope}else{'user'}
  if($default -eq 'user') { $result.MSIINSTALLPERUSER='1' }
  if($Configuration.installation.scope -eq 'choice') { $result.WBTINSTALLSCOPE=$default }
 }
 return $result
}
function Get-MsiScopeDefinition($Configuration,[string]$Architecture) {
 # This bounded declarative model is consumed by authoring and inspection. Tests
 # additionally assert native property semantics and ordering independently.
 # Remember the last selected scope so Back preserves edited destinations unless
 # the user actually switches context. An initial command-line path is honored.
 @{
  Dialog=@{Columns=@('Dialog','HCentering','VCentering','Width','Height','Attributes','Title','Control_First','Control_Default','Control_Cancel');Rows=@(
   ,@('WbtScope',50,50,400,290,3,'[ProductName] Setup','ScopeChoice','Continue','Cancel'))}
  Control=@{Columns=@('Dialog_','Control','Type','X','Y','Width','Height','Attributes','Property','Text','Control_Next');Rows=@(
   @('WbtScope','Message','Text',20,16,360,25,3,$null,'{\WbtHeading}Installation scope',$null),
   @('WbtScope','Subtitle','Text',20,44,360,34,3,$null,'Choose who can use [ProductName]. Changing scope later requires uninstalling first.',$null),
   @('WbtScope','ScopeChoice','RadioButtonGroup',20,94,360,105,3,'WBTINSTALLSCOPE',$null,'Continue'),
   @('WbtScope','Continue','PushButton',226,254,74,23,3,$null,'&Continue','Cancel'),
   @('WbtScope','Cancel','PushButton',308,254,74,23,3,$null,'Cancel','Back'),
   @('WbtScope','Back','PushButton',144,254,74,23,3,$null,'&Back','ScopeChoice'),
   @('WbtScope','FooterLine','Line',0,242,400,0,1,$null,$null,$null),
   @('WbtScope','Publisher','Text',20,260,115,18,3,$null,'[Manufacturer]',$null))}
  RadioButton=@{Columns=@('Property','Order','Value','X','Y','Width','Height','Text','Help');Rows=@(
   @('WBTINSTALLSCOPE',1,'user',0,0,340,24,'Just &me',$null),
   @('WBTINSTALLSCOPE',2,'machine',0,32,340,24,'&All users',$null))}
  ControlEvent=@{Columns=@('Dialog_','Control_','Event','Argument','Condition','Ordering');Rows=@(
   @('WbtScope','Continue','[ALLUSERS]','2','WBTINSTALLSCOPE="user" OR WBTINSTALLSCOPE="machine"',1),
   @('WbtScope','Continue','[MSIINSTALLPERUSER]','1','WBTINSTALLSCOPE="user"',2),
   @('WbtScope','Continue','[MSIINSTALLPERUSER]','{}','WBTINSTALLSCOPE="machine"',3),
   @('WbtScope','Continue','[WBTINSTALLPATH]','[INSTALLFOLDER]','NOT WBTINSTALLPATH AND INSTALLFOLDER',4),
   @('WbtScope','Continue','[WBTINSTALLPATH]',(Get-MsiDefaultInstallPath $Configuration $Architecture user),'WBTINSTALLSCOPE="user" AND (NOT WBTINSTALLPATH OR (WBTSELECTEDSCOPE AND WBTSELECTEDSCOPE <> WBTINSTALLSCOPE))',5),
   @('WbtScope','Continue','[WBTINSTALLPATH]',(Get-MsiDefaultInstallPath $Configuration $Architecture machine),'WBTINSTALLSCOPE="machine" AND (NOT WBTINSTALLPATH OR (WBTSELECTEDSCOPE AND WBTSELECTEDSCOPE <> WBTINSTALLSCOPE))',6),
   @('WbtScope','Continue','[WBTSELECTEDSCOPE]','[WBTINSTALLSCOPE]','1',7),
   @('WbtScope','Continue','NewDialog','WbtOptions','WBTINSTALLSCOPE="user" OR WBTINSTALLSCOPE="machine"',8),
   @('WbtScope','Back','NewDialog','WbtWelcome','1',1),
   @('WbtScope','Cancel','SpawnDialog','WbtCancelConfirm','1',1))}
  InstallUISequence=@{Columns=@('Action','Condition','Sequence');Rows=@()}
 }
}
function Add-MsiScopeUi($Installer,$Database,$Configuration,[string]$Architecture) {
 if($Configuration.schemaVersion -ne 2 -or $Configuration.installation.scope -ne 'choice') { return }
 Invoke-MsiSql $Database 'CREATE TABLE `RadioButton` (`Property` CHAR(72) NOT NULL, `Order` SHORT NOT NULL, `Value` CHAR(64) NOT NULL, `X` SHORT NOT NULL, `Y` SHORT NOT NULL, `Width` SHORT NOT NULL, `Height` SHORT NOT NULL, `Text` CHAR(64) LOCALIZABLE, `Help` CHAR(50) LOCALIZABLE PRIMARY KEY `Property`, `Order`)'
 foreach($entry in (Get-MsiScopeDefinition $Configuration $Architecture).GetEnumerator()) {
  foreach($row in $entry.Value.Rows) { Add-MsiRow $Installer $Database $entry.Key $entry.Value.Columns $row }
 }
}
function Assert-MsiScopePolicy([string]$Path,$Snapshot,$Configuration,[string]$Architecture) {
 $expected=Get-MsiScopeProperties $Configuration
 foreach($name in @('ALLUSERS','MSIINSTALLPERUSER','WBTINSTALLSCOPE')) {
  if($Snapshot.Properties[$name] -cne $expected[$name]) { throw "MSI scope property mismatch: $name." }
 }
 $ui=Read-MsiMaintenanceUi $Path
 $choice=$Configuration.schemaVersion -eq 2 -and $Configuration.installation.scope -eq 'choice'
 $definition=Get-MsiScopeDefinition $Configuration $Architecture
 foreach($name in $definition.Keys) {
  $source=switch($name) {Dialog {@($ui.Dialogs | Where-Object Dialog -CEQ WbtScope)} Control {@($ui.Controls | Where-Object Dialog_ -CEQ WbtScope)} ControlEvent {@($ui.Events | Where-Object Dialog_ -CEQ WbtScope)} RadioButton {@($ui.RadioButtons | Where-Object Property -CEQ WBTINSTALLSCOPE)} InstallUISequence {@($ui.InstallUi | Where-Object Action -CEQ WbtScope)}}
  $rows=@()
  if($choice) { $rows=$definition[$name].Rows }
  Assert-MsiRowsMatch $name @($source) $definition[$name].Columns @($rows)
 }

}
