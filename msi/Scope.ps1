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
function Get-MsiScopeDefinition {
 # This bounded declarative model is consumed by authoring and inspection. Tests
 # additionally assert native property semantics and ordering independently.
 @{
  Dialog=@{Columns=@('Dialog','HCentering','VCentering','Width','Height','Attributes','Title','Control_First','Control_Default','Control_Cancel');Rows=@(
   ,@('WbtScope',50,50,380,200,3,'[ProductName] - Installation scope','Message','Continue','Cancel'))}
  Control=@{Columns=@('Dialog_','Control','Type','X','Y','Width','Height','Attributes','Property','Text','Control_Next');Rows=@(
   @('WbtScope','Message','Text',16,16,348,40,3,$null,'Choose who can use this application. Changing scope later requires uninstalling first.','ScopeChoice'),
   @('WbtScope','ScopeChoice','RadioButtonGroup',16,64,348,64,3,'WBTINSTALLSCOPE',$null,'Continue'),
   @('WbtScope','Continue','PushButton',170,160,94,24,3,$null,'&Continue','Cancel'),
   @('WbtScope','Cancel','PushButton',276,160,88,24,3,$null,'C&ancel','Message'))}
  RadioButton=@{Columns=@('Property','Order','Value','X','Y','Width','Height','Text','Help');Rows=@(
   @('WBTINSTALLSCOPE',1,'user',0,0,340,24,'Just &me',$null),
   @('WBTINSTALLSCOPE',2,'machine',0,32,340,24,'&All users',$null))}
  ControlEvent=@{Columns=@('Dialog_','Control_','Event','Argument','Condition','Ordering');Rows=@(
   @('WbtScope','Continue','[ALLUSERS]','2','WBTINSTALLSCOPE="user" OR WBTINSTALLSCOPE="machine"',1),
   @('WbtScope','Continue','[MSIINSTALLPERUSER]','1','WBTINSTALLSCOPE="user"',2),
   @('WbtScope','Continue','[MSIINSTALLPERUSER]','{}','WBTINSTALLSCOPE="machine"',3),
   @('WbtScope','Continue','EndDialog','Return','WBTINSTALLSCOPE="user" OR WBTINSTALLSCOPE="machine"',4),
   @('WbtScope','Cancel','EndDialog','Exit','1',1))}
  InstallUISequence=@{Columns=@('Action','Condition','Sequence');Rows=@(,@('WbtScope','NOT Installed AND UILevel = 5',10))}
 }
}
function Add-MsiScopeUi($Installer,$Database,$Configuration) {
 if($Configuration.schemaVersion -ne 2 -or $Configuration.installation.scope -ne 'choice') { return }
 Invoke-MsiSql $Database 'CREATE TABLE `RadioButton` (`Property` CHAR(72) NOT NULL, `Order` SHORT NOT NULL, `Value` CHAR(64) NOT NULL, `X` SHORT NOT NULL, `Y` SHORT NOT NULL, `Width` SHORT NOT NULL, `Height` SHORT NOT NULL, `Text` CHAR(64) LOCALIZABLE, `Help` CHAR(50) LOCALIZABLE PRIMARY KEY `Property`, `Order`)'
 foreach($entry in (Get-MsiScopeDefinition).GetEnumerator()) {
  foreach($row in $entry.Value.Rows) { Add-MsiRow $Installer $Database $entry.Key $entry.Value.Columns $row }
 }
}
function Assert-MsiScopePolicy([string]$Path,$Snapshot,$Configuration) {
 $expected=Get-MsiScopeProperties $Configuration
 foreach($name in @('ALLUSERS','MSIINSTALLPERUSER','WBTINSTALLSCOPE')) {
  if($Snapshot.Properties[$name] -cne $expected[$name]) { throw "MSI scope property mismatch: $name." }
 }
 $ui=Read-MsiMaintenanceUi $Path
 $choice=$Configuration.schemaVersion -eq 2 -and $Configuration.installation.scope -eq 'choice'
 $definition=Get-MsiScopeDefinition
 foreach($name in $definition.Keys) {
  $source=switch($name) {Dialog {@($ui.Dialogs | Where-Object Dialog -CEQ WbtScope)} Control {@($ui.Controls | Where-Object Dialog_ -CEQ WbtScope)} ControlEvent {@($ui.Events | Where-Object Dialog_ -CEQ WbtScope)} RadioButton {@($ui.RadioButtons)} InstallUISequence {@($ui.InstallUi | Where-Object Action -CEQ WbtScope)}}
  $rows=@()
  if($choice) { $rows=$definition[$name].Rows }
  Assert-MsiRowsMatch $name @($source) $definition[$name].Columns @($rows)
 }
 if(!$choice -and 'RadioButton' -in $ui.Tables) { throw 'Unexpected MSI scope table.' }
}
