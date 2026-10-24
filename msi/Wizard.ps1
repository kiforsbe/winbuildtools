#requires -Version 7.4
<#
.SYNOPSIS
Complete bounded native Windows Installer setup and servicing dialog model.
.DESCRIPTION
New-install choices and navigation complete before discovery/costing. Only the
final Ready button returns to the engine sequence. Existing-install servicing is
routed after costing; it never offers scope/path changes. Modeless progress uses
real MSI events. Cancel asks the engine to exit/roll back, never kills a process.
This module authors no installation transaction or executable custom action.
Presentation adds only an explicitly enabled native launch choice on success.
#>
function Get-MsiWizardColumns {
 @{
  Dialog=@('Dialog','HCentering','VCentering','Width','Height','Attributes','Title','Control_First','Control_Default','Control_Cancel')
  Control=@('Dialog_','Control','Type','X','Y','Width','Height','Attributes','Property','Text','Control_Next','Help')
  ControlEvent=@('Dialog_','Control_','Event','Argument','Condition','Ordering')
  ControlCondition=@('Dialog_','Control_','Action','Condition')
  EventMapping=@('Dialog_','Control_','Event','Attribute')
  RadioButton=@('Property','Order','Value','X','Y','Width','Height','Text','Help')
  CheckBox=@('Property','Value')
  TextStyle=@('TextStyle','FaceName','Size','Color','StyleBits')
  ActionText=@('Action','Description','Template')
  UIText=@('Key','Text')
  InstallUISequence=@('Action','Condition','Sequence')
  AdminUISequence=@('Action','Condition','Sequence')
 }
}
function ConvertTo-MsiFormattedLiteral([string]$Text) {
 # Configuration directory segments may contain brackets. Escape these instead
 # of letting a product name become a formatted MSI property reference.
 [regex]::Replace($Text,'[\[\]]',{param($m) '[\'+$m.Value+']'})
}
function Get-MsiDefaultInstallPath($Configuration,[string]$Architecture,[string]$Scope) {
 $name=$Configuration.installation.directoryName
 if($Configuration.schemaVersion -eq 1) { $name+=' ('+$Architecture.ToLowerInvariant()+')' }
 $root=if($Scope -eq 'user') {'[LocalAppDataFolder]Programs\'}else{'[ProgramFiles64Folder]'}
 $root+(ConvertTo-MsiFormattedLiteral $name)+'\'
}
function ConvertTo-MsiLicenseRtf([string]$Text) {
 # Accept plain consumer text, never consumer-authored RTF commands/objects.
 # Signed UTF16 escapes keep Unicode license text independent of MSI codepage.
 $builder=[Text.StringBuilder]::new('{\rtf1\ansi\deff0{\fonttbl{\f0 Segoe UI;}}\f0\fs18 ')
 foreach($character in $Text.ToCharArray()) {
  $value=[int]$character
  if($character -eq "`r") { continue }
  if($character -eq "`n") { [void]$builder.Append('\par ') }
  elseif($character -in @('\','{','}')) { [void]$builder.Append('\'+$character) }
  elseif($value -gt 127) { if($value -gt 32767) {$value-=65536};[void]$builder.Append('\u'+$value+'?') }
  else { [void]$builder.Append($character) }
 }
 [void]$builder.Append('}');$builder.ToString()
}
function Get-MsiWizardDefinition($Configuration,[string]$Architecture) {
 $model=@{}
 foreach($entry in (Get-MsiWizardColumns).GetEnumerator()) { $model[$entry.Key]=@{Columns=$entry.Value;Rows=[Collections.Generic.List[object]]::new()} }
 function Row([string]$Table,[object[]]$Values) { $model[$Table].Rows.Add($Values) }
 function Control([string]$Dialog,[string]$Name,[string]$Type,[int]$X,[int]$Y,[int]$Width,[int]$Height,[int]$Attributes,[object]$Property,[object]$Text,[object]$Next=$null) {
  Row Control @($Dialog,$Name,$Type,$X,$Y,$Width,$Height,$Attributes,$Property,$Text,$Next,$null)
 }
 function Event([string]$Dialog,[string]$Control,[string]$Name,[string]$Argument,[string]$Condition='1',[int]$Order=1) { Row ControlEvent @($Dialog,$Control,$Name,$Argument,$Condition,$Order) }
 function Page([string]$Name,[string]$Heading,[string]$Subtitle,[string]$First='Next',[string]$Default='Next',[string]$Cancel='Cancel',[int]$Attributes=3) {
  Row Dialog @($Name,50,50,400,290,$Attributes,'[ProductName] Setup',$First,$Default,$Cancel)
  Control $Name Heading Text 20 16 360 23 3 $null ('{\WbtHeading}'+$Heading)
  Control $Name Subtitle Text 20 44 360 34 3 $null $Subtitle
  Control $Name HeaderLine Line 0 78 400 0 1 $null $null
  Control $Name FooterLine Line 0 242 400 0 1 $null $null
  Control $Name Publisher Text 20 260 115 18 3 $null '[Manufacturer]'
 }
 function Buttons([string]$Name,[string]$NextText,[bool]$Back=$true) {
  Control $Name Back PushButton 144 254 74 23 $(if($Back){3}else{1}) $null '&Back' Next
  Control $Name Next PushButton 226 254 74 23 3 $null $NextText Cancel
  Control $Name Cancel PushButton 308 254 74 23 3 $null 'Cancel' Back
  Event $Name Cancel SpawnDialog WbtCancelConfirm
 }
 $choice=$Configuration.schemaVersion -eq 2 -and $Configuration.installation.scope -eq 'choice'
 $license=[string]$Configuration.ui.licenseText
 $editable=$Configuration.ui.allowDirectoryChange -eq $true
 $firstOptions=if($editable){'WbtOptions'}elseif($license){'WbtLicense'}else{'WbtReady'}
 $beforeLicense=if($editable){'WbtOptions'}elseif($choice){'WbtScope'}else{'WbtWelcome'}
 Row TextStyle @('WbtHeading','Segoe UI',12,$null,1)
 Row UIText @('TimeRemaining','Time remaining: [1] minutes [2] seconds')

 Page WbtWelcome 'Welcome to [ProductName] Setup' 'Setup will install [ProductName] [ProductVersion] on your computer.'
 Control WbtWelcome Message Text 20 95 360 95 3 $null 'Select Next to continue. Setup will ask if an application needs to close during installation.'
 Buttons WbtWelcome '&Next' $false
 if($choice) { Event WbtWelcome Next NewDialog WbtScope }
 else {
  # Initialize once. Respect a command-line destination and preserve edits when
  # navigating Back through Welcome; costing has not started yet.
  Event WbtWelcome Next '[WBTINSTALLPATH]' '[INSTALLFOLDER]' 'NOT WBTINSTALLPATH AND INSTALLFOLDER' 1
  Event WbtWelcome Next '[WBTINSTALLPATH]' (Get-MsiDefaultInstallPath $Configuration $Architecture user) 'NOT WBTINSTALLPATH AND (NOT ALLUSERS OR (ALLUSERS = 2 AND MSIINSTALLPERUSER = 1))' 2
  Event WbtWelcome Next '[WBTINSTALLPATH]' (Get-MsiDefaultInstallPath $Configuration $Architecture machine) 'NOT WBTINSTALLPATH AND (ALLUSERS = 1 OR (ALLUSERS = 2 AND NOT MSIINSTALLPERUSER))' 3
  Event WbtWelcome Next NewDialog $firstOptions '1' 4
 }
 # A fixed destination is shown once on Ready. Only author Options when it has
 # an editable choice; every Back/forward route follows the same optional chain.
 if($editable) {
 Page WbtOptions 'Installation options' 'Review the destination for this installation.' $(if($editable){'Path'}else{'Next'})
 Control WbtOptions FolderLabel Text 20 94 360 20 3 $null 'Destination folder:'
 if($editable) { Control WbtOptions Path Edit 20 118 360 28 3 WBTINSTALLPATH $null Back }
 else { Control WbtOptions Path Text 20 118 360 42 3 $null '[WBTINSTALLPATH]' }
 Control WbtOptions ScopeInfo Text 20 173 360 48 3 $null 'The application will be installed for the selected Windows installation context. Changing scope later requires uninstalling the previous installation.'
 Buttons WbtOptions '&Next'
 if($editable) {
  # Include the path editor in the active-control cycle; disabled Back is skipped
  # by MSI. The destination remains an input until costing validates it.
  $cancel=@($model.Control.Rows | Where-Object { $_[0] -ceq 'WbtOptions' -and $_[1] -ceq 'Cancel' })[0]
  $cancel[10]='Path'
 }
 Event WbtOptions Back NewDialog $(if($choice){'WbtScope'}else{'WbtWelcome'})
 Event WbtOptions Next NewDialog $(if($license){'WbtLicense'}else{'WbtReady'}) 'WBTINSTALLPATH' 1
 }
 if($license) {
  Page WbtLicense 'License agreement' 'Read the agreement before continuing.' License
  Control WbtLicense License ScrollableText 20 88 360 119 3 $null (ConvertTo-MsiLicenseRtf $license) Accept
  Control WbtLicense Accept CheckBox 20 215 360 18 3 WBTACCEPTLICENSE 'I &accept the license agreement' Back
  Row CheckBox @('WBTACCEPTLICENSE','1')
  Buttons WbtLicense '&Next'
  $cancel=@($model.Control.Rows | Where-Object {$_[0] -ceq 'WbtLicense' -and $_[1] -ceq 'Cancel'})[0];$cancel[10]='License'
  Row ControlCondition @('WbtLicense','Next','Disable','NOT (WBTACCEPTLICENSE = 1)')
  Row ControlCondition @('WbtLicense','Next','Enable','WBTACCEPTLICENSE = 1')
  Event WbtLicense Back NewDialog $beforeLicense
  Event WbtLicense Next NewDialog WbtReady 'WBTACCEPTLICENSE = 1'
 }
 Page WbtReady 'Ready to install [ProductName]' 'Select Install to validate your choices and begin installation.'
 Control WbtReady Details Text 20 92 360 95 3 $null "Application: [ProductName] [ProductVersion]`r`nDestination: [WBTINSTALLPATH]"
 Control WbtReady Elevation Text 20 193 360 36 3 $null 'Windows may request administrator approval if this installation requires it.'
 Buttons WbtReady '&Install'
 Event WbtReady Back NewDialog $(if($license){'WbtLicense'}else{$beforeLicense})
 Event WbtReady Next '[INSTALLFOLDER]' '[WBTINSTALLPATH]' 'WBTINSTALLPATH' 1
 Event WbtReady Next EndDialog Return 'WBTINSTALLPATH' 2

 # These pages are scheduled after native discovery/costing. New-install choices
 # are no longer revisited here; maintenance never rewrites scope or destination.
 # KeepModeless (16) preserves early progress while a post-cost modal choice is
 # open. Result pages intentionally omit it so they replace the progress window.
 Page WbtMaintenance 'Maintain [ProductName]' 'Choose the operation for the installed application.' Mode -Attributes 19
 Control WbtMaintenance Mode RadioButtonGroup 20 94 360 115 3 WBTMAINTENANCE $null Next
 Row RadioButton @('WBTMAINTENANCE',1,'repair',0,0,348,42,'&Repair application files and shortcuts',$null)
 Row RadioButton @('WBTMAINTENANCE',2,'remove',0,58,348,42,'&Remove the installed application',$null)
 Buttons WbtMaintenance '&Next' $false
 $cancel=@($model.Control.Rows | Where-Object {$_[0] -ceq 'WbtMaintenance' -and $_[1] -ceq 'Cancel'})[0];$cancel[10]='Mode'
  $back=@($model.Control.Rows | Where-Object {$_[0] -ceq 'WbtMaintenance' -and $_[1] -ceq 'Back'})[0];$back[10]=$null
 Event WbtMaintenance Next '[WBTMAINTENANCEUI]' '1' '1' 1
 Event WbtMaintenance Next '[REMOVE]' '{}' 'WBTMAINTENANCE = "repair"' 2
 Event WbtMaintenance Next '[REINSTALL]' 'ALL' 'WBTMAINTENANCE = "repair"' 3
 Event WbtMaintenance Next '[REINSTALLMODE]' 'amus' 'WBTMAINTENANCE = "repair"' 4
 Event WbtMaintenance Next '[REINSTALL]' '{}' 'WBTMAINTENANCE = "remove"' 5
 Event WbtMaintenance Next '[REMOVE]' 'ALL' 'WBTMAINTENANCE = "remove"' 6
 Event WbtMaintenance Next NewDialog WbtRepair 'WBTMAINTENANCE = "repair"' 7
 Event WbtMaintenance Next NewDialog WbtRemove 'WBTMAINTENANCE = "remove"' 8
 foreach($name in @('WbtRemove','WbtRepair','WbtUpgrade')) {
  $title=switch($name) {WbtRemove {'Remove [ProductName]?'} WbtRepair {'Ready to repair [ProductName]'} WbtUpgrade {'Ready to upgrade [ProductName]'}}
  $verb=switch($name) {WbtRemove {'&Remove'} WbtRepair {'&Repair'} WbtUpgrade {'&Upgrade'}}
  $message=switch($name) {WbtRemove {'The installed application and its shortcuts will be removed. Personal application data will be kept.'} WbtRepair {'Windows Installer will restore missing or damaged application files and shortcuts. Personal application data will be kept.'} WbtUpgrade {'An earlier version was detected in this installation context. It will be replaced by [ProductName] [ProductVersion]. Personal application data will be kept.'}}
  Page $name $title 'Confirm the operation before continuing.' -Attributes 19
  Control $name Message Text 20 94 360 85 3 $null $message
  Control $name Location Text 20 188 360 36 3 $null 'Installation folder: [INSTALLFOLDER]'
  Buttons $name $verb ($name -ne 'WbtUpgrade')
  if($name -ne 'WbtUpgrade') {
   Event $name Back '[REMOVE]' '{}' '1' 1
   Event $name Back '[REINSTALL]' '{}' '1' 2
   Event $name Back NewDialog WbtMaintenance '1' 3
  }
  if($name -eq 'WbtRepair') {
   Event $name Next ReinstallMode amus '1' 1
   Event $name Next Reinstall ALL '1' 2
   Event $name Next EndDialog Return '1' 3
  } elseif($name -eq 'WbtRemove') {
   Event $name Next Remove ALL '1' 1
   Event $name Next EndDialog Return '1' 2
  } else { Event $name Next EndDialog Return }
 }

 Page WbtProgress 'Applying changes to [ProductName]' 'Please wait while Windows Installer completes the operation.' Cancel Cancel Cancel 1
 Control WbtProgress Action Text 20 99 360 36 3 $null 'Preparing application files...'
 Control WbtProgress Progress ProgressBar 20 146 360 15 65537 $null $null
 Control WbtProgress Detail Text 20 172 360 33 3 $null ' '
 Control WbtProgress Remaining Text 20 211 360 19 3 $null ' '
 Control WbtProgress Cancel PushButton 308 254 74 23 3 $null 'Cancel' Cancel
 Event WbtProgress Cancel SpawnDialog WbtCancelConfirm 'UILevel = 5' 1
 # EndDialog/SpawnDialog require full UI. Reduced UI can display progress but
 # cannot use this authored cancellation route; never leave a dead enabled button.
 Row ControlCondition @('WbtProgress','Cancel','Disable','UILevel < 5')
 Row ControlCondition @('WbtProgress','Cancel','Enable','UILevel = 5')
 Row EventMapping @('WbtProgress','Progress','SetProgress','Progress')
 Row EventMapping @('WbtProgress','Action','ActionText','Text')
 Row EventMapping @('WbtProgress','Detail','ActionData','Text')
 Row EventMapping @('WbtProgress','Remaining','TimeRemaining','TimeRemaining')
 # ProgressBar direction/ticks, including reversed rollback progress, come from
 # MSI's SetProgress event. No guessed percentage, timer, or forced process exit.
 Page WbtCancelConfirm 'Cancel setup?' 'Do you want to stop the current operation?' Continue Continue Continue 19
 Control WbtCancelConfirm Message Text 20 96 360 95 3 $null 'If changes have already begun, Windows Installer will attempt to undo them. Select Continue setup to keep going.'
 Control WbtCancelConfirm Continue PushButton 186 254 114 23 3 $null '&Continue setup' Yes
 Control WbtCancelConfirm Yes PushButton 308 254 74 23 3 $null 'Cancel &setup' Continue
 Event WbtCancelConfirm Continue EndDialog Return
 Event WbtCancelConfirm Yes EndDialog Exit

 Row InstallUISequence @('WbtWelcome','NOT Installed AND UILevel = 5',5)
 Row InstallUISequence @('WbtMaintenance','Installed AND NOT REMOVE AND NOT REINSTALL AND UILevel = 5',1220)
 Row InstallUISequence @('WbtRemove','Installed AND REMOVE~="ALL" AND NOT WBTMAINTENANCEUI AND UILevel = 5',1221)
 Row InstallUISequence @('WbtRepair','Installed AND REINSTALL AND NOT REMOVE AND NOT WBTMAINTENANCEUI AND UILevel = 5',1222)
 Row InstallUISequence @('WbtUpgrade','NOT Installed AND OLDERVERSIONS AND UILevel = 5',1230)
 # Keep the modeless window present while discovery/costing prepares the server
 # transaction. New installs reach this only after Ready's explicit Install;
 # maintenance/reduced UI also use this single row, with no second progress page.
 Row InstallUISequence @('WbtProgress','UILevel >= 4',10)
 foreach($result in @(
  @('WbtExit',-1,'Setup completed','The requested operation completed.','Select Finish to close setup.'),
  @('WbtUserExit',-2,'Setup canceled','The requested operation was canceled.','Windows Installer attempts to undo changes when an operation is canceled. Review the log if a restart or recovery is required.'),
  @('WbtFatalError',-3,'Setup could not complete','The requested operation did not complete.','Review the error details and installation log before retrying. Do not use incomplete output as a successful installation.')
 )) {
  $name=[string]$result[0]
  Page $name ([string]$result[2]) ([string]$result[3]) Finish Finish Finish
  Control $name Message Text 20 97 360 57 3 $null $result[4]
  Control $name Log Text 20 160 360 39 3 $null 'Installation log: [MsiLogFileLocation]'
  Control $name Restart Text 20 203 360 33 3 $null 'Restart Windows to finish applying changes.'
  Control $name Finish PushButton 308 254 74 23 3 $null '&Finish' Finish
  Event $name Finish EndDialog Return
  Row ControlCondition @($name,'Log','Hide','NOT MsiLogFileLocation')
  Row ControlCondition @($name,'Log','Show','MsiLogFileLocation')
  Row ControlCondition @($name,'Restart','Hide','NOT ReplacedInUseFiles')
  Row ControlCondition @($name,'Restart','Show','ReplacedInUseFiles')
  foreach($sequence in @('InstallUISequence','AdminUISequence')) { Row $sequence @($name,'UILevel = 5',[int]$result[1]) }
 }
 foreach($entry in @(
  @('InstallFiles','Copying application files','File: [1]'),
  @('RemoveFiles','Removing installed application files','File: [1]'),
  @('CreateShortcuts','Creating application shortcuts','Shortcut: [1]'),
  @('RemoveShortcuts','Removing installed application shortcuts','Shortcut: [1]'),
  @('RegisterProduct','Registering [ProductName]',' '),
  @('PublishProduct','Updating Windows application registration',' '),
  @('RemoveExistingProducts','Removing the previous application version',' '),
  @('Rollback','Undoing changes made by this operation',' ')
 )) { Row ActionText $entry }
 Update-MsiPresentationModel $model $Configuration $Architecture
 return $model
}
function Add-MsiWizardUi($Installer,$Database,$Configuration,[string]$Architecture) {
 $schemas=@{
  EventMapping='`Dialog_` CHAR(72) NOT NULL, `Control_` CHAR(50) NOT NULL, `Event` CHAR(50) NOT NULL, `Attribute` CHAR(50) NOT NULL PRIMARY KEY `Dialog_`, `Control_`, `Event`'
  ControlCondition='`Dialog_` CHAR(72) NOT NULL, `Control_` CHAR(50) NOT NULL, `Action` CHAR(50) NOT NULL, `Condition` CHAR(255) NOT NULL PRIMARY KEY `Dialog_`, `Control_`, `Action`, `Condition`'
  RadioButton='`Property` CHAR(72) NOT NULL, `Order` SHORT NOT NULL, `Value` CHAR(64) NOT NULL, `X` SHORT NOT NULL, `Y` SHORT NOT NULL, `Width` SHORT NOT NULL, `Height` SHORT NOT NULL, `Text` CHAR(64) LOCALIZABLE, `Help` CHAR(50) LOCALIZABLE PRIMARY KEY `Property`, `Order`'
  CheckBox='`Property` CHAR(72) NOT NULL, `Value` CHAR(64) PRIMARY KEY `Property`'
  ActionText='`Action` CHAR(72) NOT NULL, `Description` CHAR(64) LOCALIZABLE, `Template` CHAR(128) LOCALIZABLE PRIMARY KEY `Action`'
  UIText='`Key` CHAR(72) NOT NULL, `Text` CHAR(255) NOT NULL LOCALIZABLE PRIMARY KEY `Key`'
 }
 $tables=@(Get-MsiRows $Database _Tables @('Name') | ForEach-Object Name)
 foreach($entry in $schemas.GetEnumerator()) { if($entry.Key -notin $tables) { Invoke-MsiSql $Database ('CREATE TABLE `{0}` ({1})' -f $entry.Key,$entry.Value) } }
 # Scope is a page in the Welcome chain; Continue skips absent optional pages. This
 # chain returns only after final confirmation, before FindRelatedProducts/costing.
 Invoke-MsiSql $Database 'DELETE FROM `InstallUISequence` WHERE `Action`=''WbtScope'''
 foreach($entry in (Get-MsiWizardDefinition $Configuration $Architecture).GetEnumerator()) {
  foreach($row in $entry.Value.Rows) {
   try { Add-MsiRow $Installer $Database $entry.Key $entry.Value.Columns $row }
   catch { throw "Cannot author wizard table $($entry.Key), key $($row[0]): $_" }
  }
 }
 Add-MsiRow $Installer $Database Property @('Property','Value') @('WBTMAINTENANCE','repair')
 if($Configuration.ui.licenseText) {
  Add-MsiRow $Installer $Database LaunchCondition @('Condition','Description') @('Installed OR UILevel = 5 OR WBTACCEPTLICENSE = 1','Unattended installation requires explicit WBTACCEPTLICENSE=1 acceptance of the supplied license.')
 }
}
function Assert-MsiWizardPolicy([string]$Path,$Configuration,[string]$Architecture) {
 $installer=$null;$database=$null
 try {
  $installer=New-Object -ComObject WindowsInstaller.Installer;$database=$installer.OpenDatabase($Path,0)
  $definition=Get-MsiWizardDefinition $Configuration $Architecture
  foreach($name in $definition.Keys) {
   $rows=@(Get-MsiRows $database $name $definition[$name].Columns)
   switch($name) {
    Dialog { $rows=@($rows | Where-Object Dialog -notin @('MsiRMFilesInUse','FilesInUse','WbtError','WbtScope')) }
    Control { $rows=@($rows | Where-Object Dialog_ -notin @('MsiRMFilesInUse','FilesInUse','WbtError','WbtScope')) }
    ControlEvent { $rows=@($rows | Where-Object Dialog_ -notin @('MsiRMFilesInUse','FilesInUse','WbtError','WbtScope')) }
    RadioButton { $rows=@($rows | Where-Object Property -CNE WBTINSTALLSCOPE) }
    TextStyle { $rows=@($rows | Where-Object TextStyle -CNE WbtUIFont) }
    InstallUISequence { $rows=@($rows | Where-Object Action -in @($definition.InstallUISequence.Rows | ForEach-Object {$_[0]})) }
   }
   Assert-MsiRowsMatch ('wizard '+$name) $rows $definition[$name].Columns $definition[$name].Rows.ToArray()
  }
 } finally { Close-MsiCom $database;Close-MsiCom $installer }
}
