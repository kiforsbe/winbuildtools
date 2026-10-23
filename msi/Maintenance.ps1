#requires -Version 7.4

<#
.SYNOPSIS
Native Windows Installer files-in-use UI authoring and maintenance policy checks.
.DESCRIPTION
Dot-source after Database.ps1. These helpers author/read standard MSI tables only;
they do not open an installation session, invoke Restart Manager or stop processes.
Full UI uses the reserved dialogs. Basic/silent interaction is engine-owned;
reduced UI can also use the authored error and legacy FilesInUse dialogs.
#>
function Add-MsiMaintenanceUi($Installer,$Database) {
 # Dialog/control identifiers and event arguments are engine-owned constants.
 # FileInUseProcess is populated by InstallValidate, not by product configuration.
 $schemas=@{
  Dialog='`Dialog` CHAR(72) NOT NULL, `HCentering` SHORT NOT NULL, `VCentering` SHORT NOT NULL, `Width` SHORT NOT NULL, `Height` SHORT NOT NULL, `Attributes` LONG, `Title` CHAR(128) LOCALIZABLE, `Control_First` CHAR(50) NOT NULL, `Control_Default` CHAR(50), `Control_Cancel` CHAR(50) PRIMARY KEY `Dialog`'
  Control='`Dialog_` CHAR(72) NOT NULL, `Control` CHAR(50) NOT NULL, `Type` CHAR(20) NOT NULL, `X` SHORT NOT NULL, `Y` SHORT NOT NULL, `Width` SHORT NOT NULL, `Height` SHORT NOT NULL, `Attributes` LONG, `Property` CHAR(72), `Text` CHAR(0) LOCALIZABLE, `Control_Next` CHAR(50), `Help` CHAR(50) LOCALIZABLE PRIMARY KEY `Dialog_`, `Control`'
  ControlEvent='`Dialog_` CHAR(72) NOT NULL, `Control_` CHAR(50) NOT NULL, `Event` CHAR(50) NOT NULL, `Argument` CHAR(255) NOT NULL, `Condition` CHAR(255), `Ordering` SHORT PRIMARY KEY `Dialog_`, `Control_`, `Event`, `Argument`, `Condition`'
  ListBox='`Property` CHAR(72) NOT NULL, `Order` SHORT NOT NULL, `Value` CHAR(64) NOT NULL, `Text` CHAR(64) LOCALIZABLE PRIMARY KEY `Property`, `Order`'
  TextStyle='`TextStyle` CHAR(72) NOT NULL, `FaceName` CHAR(32) NOT NULL, `Size` SHORT NOT NULL, `Color` LONG, `StyleBits` SHORT PRIMARY KEY `TextStyle`'
  AdminUISequence='`Action` CHAR(72) NOT NULL, `Condition` CHAR(255), `Sequence` SHORT PRIMARY KEY `Action`'
 }
 foreach($table in $schemas.Keys) { Invoke-MsiSql $Database ('CREATE TABLE `{0}` ({1})' -f $table,$schemas[$table]) }
 Add-MsiRow $Installer $Database Property @('Property','Value') @('DefaultUIFont','WbtUIFont')
 Add-MsiRow $Installer $Database TextStyle @('TextStyle','FaceName','Size') @('WbtUIFont','Segoe UI',9)
 foreach($dialog in @('MsiRMFilesInUse','FilesInUse')) {
  $useRm=$dialog -ceq 'MsiRMFilesInUse'
  $primary=if($useRm) {'Close'}else{'Retry'}
  $buttonText=if($useRm) {'&Close applications'}else{'&Retry'}
  $message=if($useRm) {
   'Setup needs files used by these applications. Save your work, then choose Close applications to request shutdown. Applications will not be reopened automatically. To close them yourself, cancel setup and try again.'
  }else{
   'Close the applications listed below, including tray icons, then choose Retry. Continue without closing may require a reboot. Cancel exits setup.'
  }
  # 19 = Visible | Modal | KeepModeless. Cancel is the safe Enter/Escape default;
  # the message precedes the list in the closed tab cycle for screen readers.
  Add-MsiRow $Installer $Database Dialog @('Dialog','HCentering','VCentering','Width','Height','Attributes','Title','Control_First','Control_Default','Control_Cancel') @($dialog,50,50,380,240,19,'[ProductName] - Files in use','Message','Cancel','Cancel')
  $columns=@('Dialog_','Control','Type','X','Y','Width','Height','Attributes','Property','Text','Control_Next')
  Add-MsiRow $Installer $Database Control $columns @($dialog,'Message','Text',16,16,348,60,3,$null,$message,'Processes')
  Add-MsiRow $Installer $Database Control $columns @($dialog,'Processes','ListBox',16,80,348,104,7,'FileInUseProcess','Applications using files',$primary)
  $primaryX=if($useRm) {126}else{16}
  $primaryWidth=if($useRm) {140}else{100}
  $primaryNext=if($useRm) {'Cancel'}else{'Ignore'}
  Add-MsiRow $Installer $Database Control $columns @($dialog,$primary,'PushButton',$primaryX,204,$primaryWidth,24,3,$null,$buttonText,$primaryNext)
  if(!$useRm) { Add-MsiRow $Installer $Database Control $columns @($dialog,'Ignore','PushButton',126,204,140,24,3,$null,'Continue &without closing','Cancel') }
  Add-MsiRow $Installer $Database Control $columns @($dialog,'Cancel','PushButton',276,204,88,24,3,$null,'C&ancel','Message')
  $eventColumns=@('Dialog_','Control_','Event','Argument','Condition','Ordering')
  # EndDialog Return closes the reserved RM dialog; RMShutdownAndRestart is the
  # documented native consent event. MSIDISABLERMRESTART suppresses the restart
  # part, and MSIRMSHUTDOWN=0 keeps shutdown non-forceful. Never call RmShutdown.
  $returnValue=if($useRm) {'Return'}else{'Retry'}
  Add-MsiRow $Installer $Database ControlEvent $eventColumns @($dialog,$primary,'EndDialog',$returnValue,'1',1)
  if($useRm) { Add-MsiRow $Installer $Database ControlEvent $eventColumns @($dialog,$primary,'RMShutdownAndRestart','0','1',2) }
  # ICE20 requires the legacy Ignore result. It is an explicit continuation
  # choice (possibly deferring file removal until reboot), never forced shutdown.
  if(!$useRm) { Add-MsiRow $Installer $Database ControlEvent $eventColumns @($dialog,'Ignore','EndDialog','Ignore','1',1) }
  Add-MsiRow $Installer $Database ControlEvent $eventColumns @($dialog,'Cancel','EndDialog','Exit','1',1)
 }
 # An authored Dialog table also requires generic error/result UI (ICE20).
 # Windows selects/repositions the appropriate subset of these seven buttons;
 # error controls deliberately have no Control_Next cycle.
 Add-MsiRow $Installer $Database Property @('Property','Value') @('ErrorDialog','WbtError')
 Add-MsiRow $Installer $Database Dialog @('Dialog','HCentering','VCentering','Width','Height','Attributes','Title','Control_First') @('WbtError',50,50,380,200,65539,'[ProductName] - Setup message','ErrorText')
 Add-MsiRow $Installer $Database Control $columns @('WbtError','ErrorText','Text',16,16,348,128,3,$null,' ',$null)
 $errorButtons=[ordered]@{A=@('Abort','&Abort');C=@('Cancel','&Cancel');I=@('Ignore','&Ignore');N=@('No','&No');O=@('Ok','&OK');R=@('Retry','&Retry');Y=@('Yes','&Yes')}
 foreach($button in $errorButtons.GetEnumerator()) {
  Add-MsiRow $Installer $Database Control $columns @('WbtError',$button.Key,'PushButton',16,164,80,24,3,$null,$button.Value[1],$null)
  Add-MsiRow $Installer $Database ControlEvent $eventColumns @('WbtError',$button.Key,'EndDialog',('Error'+$button.Value[0]),'1',1)
 }
 # Termination dialogs do not launch anything or change the installation result.
 # AdminUISequence gets the required result entries, not an administrative
 # installation implementation. No executable custom actions are introduced.
 foreach($result in @(@('WbtExit',-1,'Setup completed. Review the installation result and log for any required restart.'),@('WbtUserExit',-2,'Setup was canceled. Review the log before retrying.'),@('WbtFatalError',-3,'Setup could not complete. Review the error details and log before retrying.'))) {
  Add-MsiRow $Installer $Database Dialog @('Dialog','HCentering','VCentering','Width','Height','Attributes','Title','Control_First','Control_Default','Control_Cancel') @($result[0],50,50,380,160,3,'[ProductName] - Setup','Finish','Finish','Finish')
  Add-MsiRow $Installer $Database Control $columns @($result[0],'Message','Text',16,16,348,80,3,$null,$result[2],'Finish')
  Add-MsiRow $Installer $Database Control $columns @($result[0],'Finish','PushButton',276,120,88,24,3,$null,'&Close','Message')
  Add-MsiRow $Installer $Database ControlEvent $eventColumns @($result[0],'Finish','EndDialog','Return','1',1)
  foreach($sequence in @('InstallUISequence','AdminUISequence')) {
   Add-MsiRow $Installer $Database $sequence @('Action','Condition','Sequence') @($result[0],'UILevel = 5',[int]$result[1])
  }
 }
}

function Read-MsiMaintenanceUi([string]$Path) {
 # Return plain snapshots from a read-only database; missing UI tables stay
 # distinguishable from present-but-empty tables so inspection can reject them.
 $installer=$null;$database=$null
 try {
  $installer=New-Object -ComObject WindowsInstaller.Installer
  $database=$installer.OpenDatabase($Path,0)
  $tables=@(Get-MsiRows $database _Tables @('Name') | ForEach-Object Name)
  [pscustomobject]@{
   Tables=$tables
   Dialogs=if('Dialog' -in $tables) {@(Get-MsiRows $database Dialog @('Dialog','HCentering','VCentering','Width','Height','Attributes','Title','Control_First','Control_Default','Control_Cancel'))}else{@()}
   Controls=if('Control' -in $tables) {@(Get-MsiRows $database Control @('Dialog_','Control','Type','X','Y','Width','Height','Attributes','Property','Text','Control_Next'))}else{@()}
   Events=if('ControlEvent' -in $tables) {@(Get-MsiRows $database ControlEvent @('Dialog_','Control_','Event','Argument','Condition','Ordering'))}else{@()}
   Fonts=if('TextStyle' -in $tables) {@(Get-MsiRows $database TextStyle @('TextStyle','FaceName','Size'))}else{@()}
   ListItems=if('ListBox' -in $tables) {@(Get-MsiRows $database ListBox @('Property','Order','Value','Text'))}else{@()}
   RadioButtons=if('RadioButton' -in $tables) {@(Get-MsiRows $database RadioButton @('Property','Order','Value','X','Y','Width','Height','Text','Help'))}else{@()}
   InstallUi=@(Get-MsiRows $database InstallUISequence @('Action','Condition','Sequence'))
   AdminUi=if('AdminUISequence' -in $tables) {@(Get-MsiRows $database AdminUISequence @('Action','Condition','Sequence'))}else{@()}
  }
 } finally { Close-MsiCom $database;Close-MsiCom $installer }
}

function Assert-MsiMaintenancePolicy([string]$Path,$Properties,$Configuration) {
 # Inspect production bytes before any native costing. Copy-only preflight uses
 # Disable to avoid interacting with running applications during verification.
 if($Properties.ContainsKey('LIMITUI')) { throw 'MSI maintenance policy must not suppress authored full UI with LIMITUI.' }
 $rm=if($Configuration -and $Configuration.schemaVersion -eq 2 -and $Configuration.installation.restartManager -eq 'disabled') {'Disable'}else{'0'}
 foreach($pair in @{MSIRESTARTMANAGERCONTROL=$rm;MSIRMSHUTDOWN='0';MSIDISABLERMRESTART='1';REBOOT='ReallySuppress';DefaultUIFont='WbtUIFont';ErrorDialog='WbtError'}.GetEnumerator()) {
  if($Properties[$pair.Key] -cne $pair.Value) { throw "MSI maintenance policy mismatch: $($pair.Key)." }
 }
 $ui=Read-MsiMaintenanceUi $Path
 if(@('Dialog','Control','ControlEvent','ListBox','TextStyle','AdminUISequence' | Where-Object {$_ -notin $ui.Tables}).Count) { throw 'MSI files-in-use UI tables are missing.' }
 if(@($ui.Dialogs | Where-Object Dialog -CNE WbtScope).Count -ne 6 -or @($ui.Controls | Where-Object Dialog_ -CNE WbtScope).Count -ne 23 -or @($ui.Events | Where-Object Dialog_ -CNE WbtScope).Count -ne 16 -or @($ui.Fonts).Count -ne 1 -or @($ui.ListItems).Count -ne 0) { throw 'MSI files-in-use UI contains unexpected rows.' }
 if($ui.Fonts[0].TextStyle -cne 'WbtUIFont' -or $ui.Fonts[0].FaceName -cne 'Segoe UI' -or $ui.Fonts[0].Size -ne '9') { throw 'MSI files-in-use font mismatch.' }
 foreach($dialogName in @('MsiRMFilesInUse','FilesInUse')) {
  $dialogs=@($ui.Dialogs | Where-Object Dialog -CEQ $dialogName)
  if($dialogs.Count -ne 1) { throw "MSI files-in-use dialog missing: $dialogName." }
  $dialog=$dialogs[0]
  if($dialog.Attributes -ne '19' -or $dialog.HCentering -ne '50' -or $dialog.VCentering -ne '50' -or $dialog.Control_First -cne 'Message' -or $dialog.Control_Default -cne 'Cancel' -or $dialog.Control_Cancel -cne 'Cancel' -or $dialog.Width -ne '380' -or $dialog.Height -ne '240' -or $dialog.Title -cne '[ProductName] - Files in use') { throw 'MSI files-in-use dialog/default/cancel mapping mismatch.' }
  $primary=if($dialogName -ceq 'MsiRMFilesInUse') {'Close'}else{'Retry'}
  $controls=@($ui.Controls | Where-Object Dialog_ -CEQ $dialogName)
  $controlNames=if($dialogName -ceq 'FilesInUse') {@('Message','Processes','Retry','Ignore','Cancel')}else{@('Message','Processes','Close','Cancel')}
  foreach($controlName in $controlNames) {
   $matches=@($controls | Where-Object Control -CEQ $controlName)
   if($matches.Count -ne 1) { throw 'MSI files-in-use control missing.' }
   $control=$matches[0]
   $expectedType=if($controlName -ceq 'Message') {'Text'}elseif($controlName -ceq 'Processes') {'ListBox'}else{'PushButton'}
   $next=if($controlName -ceq 'Message') {'Processes'}elseif($controlName -ceq 'Processes') {$primary}elseif($controlName -ceq $primary) {if($primary -ceq 'Retry') {'Ignore'}else{'Cancel'}}elseif($controlName -ceq 'Ignore') {'Cancel'}else{'Message'}
   $attributes=if($controlName -ceq 'Processes') {7}else{3}
   if($control.Type -cne $expectedType -or [int]$control.Attributes -ne $attributes -or $control.Control_Next -cne $next -or [int]$control.Width -le 0 -or [int]$control.Height -le 0 -or [int]$control.X -lt 0 -or [int]$control.Y -lt 0 -or ([int]$control.X+[int]$control.Width) -gt [int]$dialog.Width -or ([int]$control.Y+[int]$control.Height) -gt [int]$dialog.Height -or !$control.Text) { throw 'MSI files-in-use control layout/type/tab mapping mismatch.' }
   if(($controlName -ceq 'Processes' -and $control.Property -cne 'FileInUseProcess') -or ($controlName -cne 'Processes' -and $control.Property)) { throw 'MSI files-in-use process-list binding mismatch.' }
  }
  $events=@($ui.Events | Where-Object Dialog_ -CEQ $dialogName)
  foreach($event in $events) {
   $valid=$event.Condition -ceq '1' -and (
    ($event.Control_ -ceq 'Cancel' -and $event.Event -ceq 'EndDialog' -and $event.Argument -ceq 'Exit' -and $event.Ordering -eq '1') -or
    ($dialogName -ceq 'FilesInUse' -and $event.Control_ -ceq 'Ignore' -and $event.Event -ceq 'EndDialog' -and $event.Argument -ceq 'Ignore' -and $event.Ordering -eq '1') -or
    ($event.Control_ -ceq $primary -and $event.Event -ceq 'EndDialog' -and $event.Argument -ceq $(if($primary -ceq 'Close') {'Return'}else{'Retry'}) -and $event.Ordering -eq '1') -or
    ($dialogName -ceq 'MsiRMFilesInUse' -and $event.Control_ -ceq 'Close' -and $event.Event -ceq 'RMShutdownAndRestart' -and $event.Argument -ceq '0' -and $event.Ordering -eq '2'))
   if(!$valid) { throw 'MSI files-in-use consent/retry/cancel event mismatch.' }
  }
  if($events.Count -ne 3) { throw 'MSI files-in-use event count mismatch.' }
 }
 Assert-MsiStandardDialogs $ui
}

function Assert-MsiStandardDialogs($Ui) {
 # Verify the standard authored-UI contract as well as file-use consent. This
 # structural check is not an ICE run or proof that a real message was displayed.
 $errorDialogs=@($Ui.Dialogs | Where-Object Dialog -CEQ 'WbtError')
 if($errorDialogs.Count -ne 1 -or $errorDialogs[0].Attributes -ne '65539' -or $errorDialogs[0].Control_First -cne 'ErrorText') { throw 'MSI standard error dialog mismatch.' }
 $errorControls=@($Ui.Controls | Where-Object Dialog_ -CEQ 'WbtError')
 Assert-MsiStandardDialogLayout $errorDialogs[0] $errorControls
 $errorEvents=@($Ui.Events | Where-Object Dialog_ -CEQ 'WbtError')
 $text=@($errorControls | Where-Object Control -CEQ 'ErrorText')
 if($text.Count -ne 1 -or $text[0].Type -cne 'Text' -or $text[0].Attributes -ne '3' -or $text[0].Control_Next -or $errorControls.Count -ne 8 -or $errorEvents.Count -ne 7) { throw 'MSI standard error controls mismatch.' }
 foreach($button in @{A='ErrorAbort';C='ErrorCancel';I='ErrorIgnore';N='ErrorNo';O='ErrorOk';R='ErrorRetry';Y='ErrorYes'}.GetEnumerator()) {
  $controls=@($errorControls | Where-Object Control -CEQ $button.Key)
  if($controls.Count -ne 1 -or $controls[0].Type -cne 'PushButton' -or $controls[0].Attributes -ne '3' -or $controls[0].Control_Next -or $controls[0].Y -ne '164' -or $controls[0].Width -ne '80' -or $controls[0].Height -ne '24' -or !$controls[0].Text) { throw 'MSI standard error button mismatch.' }
  if(@($errorEvents | Where-Object { $_.Control_ -ceq $button.Key -and $_.Event -ceq 'EndDialog' -and $_.Argument -ceq $button.Value -and $_.Condition -ceq '1' -and $_.Ordering -eq '1' }).Count -ne 1) { throw 'MSI standard error result mapping mismatch.' }
 }
 foreach($result in @{WbtExit=-1;WbtUserExit=-2;WbtFatalError=-3}.GetEnumerator()) {
  $dialogs=@($Ui.Dialogs | Where-Object Dialog -CEQ $result.Key)
  if($dialogs.Count -ne 1 -or $dialogs[0].Attributes -ne '3' -or $dialogs[0].Control_First -cne 'Finish' -or $dialogs[0].Control_Default -cne 'Finish' -or $dialogs[0].Control_Cancel -cne 'Finish') { throw 'MSI standard termination dialog mismatch.' }
  $controls=@($Ui.Controls | Where-Object Dialog_ -CEQ $result.Key)
  Assert-MsiStandardDialogLayout $dialogs[0] $controls
  $message=@($controls | Where-Object Control -CEQ 'Message')
  $finish=@($controls | Where-Object Control -CEQ 'Finish')
  if($controls.Count -ne 2 -or $message.Count -ne 1 -or $finish.Count -ne 1 -or $message[0].Type -cne 'Text' -or $message[0].Attributes -ne '3' -or $message[0].Control_Next -cne 'Finish' -or !$message[0].Text -or $finish[0].Type -cne 'PushButton' -or $finish[0].Attributes -ne '3' -or $finish[0].Control_Next -cne 'Message' -or !$finish[0].Text) { throw 'MSI standard termination controls mismatch.' }
  $events=@($Ui.Events | Where-Object Dialog_ -CEQ $result.Key)
  if($events.Count -ne 1 -or $events[0].Control_ -cne 'Finish' -or $events[0].Event -cne 'EndDialog' -or $events[0].Argument -cne 'Return' -or $events[0].Condition -cne '1' -or $events[0].Ordering -ne '1') { throw 'MSI standard termination event mismatch.' }
  foreach($sequence in @('InstallUi','AdminUi')) {
   if(@($Ui.$sequence | Where-Object { $_.Action -ceq $result.Key -and [int]$_.Sequence -eq $result.Value -and $_.Condition -ceq 'UILevel = 5' }).Count -ne 1) { throw 'MSI standard termination sequence mismatch.' }
  }
 }
 if(@($Ui.InstallUi | Where-Object {[int]$_.Sequence -lt 0}).Count -ne 3 -or @($Ui.AdminUi).Count -ne 3) { throw 'MSI standard termination sequence contains unexpected rows.' }
}

function Assert-MsiStandardDialogLayout($Dialog,$Controls) {
 # Engine-selected error buttons intentionally share initial coordinates, but
 # every declared rectangle must remain visible and inside a usable dialog.
 if([int]$Dialog.Width -le 0 -or [int]$Dialog.Height -le 0 -or [int]$Dialog.HCentering -lt 0 -or [int]$Dialog.HCentering -gt 100 -or [int]$Dialog.VCentering -lt 0 -or [int]$Dialog.VCentering -gt 100) { throw 'MSI standard dialog layout mismatch.' }
 foreach($control in $Controls) {
  if([int]$control.Width -le 0 -or [int]$control.Height -le 0 -or [int]$control.X -lt 0 -or [int]$control.Y -lt 0 -or ([int]$control.X+[int]$control.Width) -gt [int]$Dialog.Width -or ([int]$control.Y+[int]$control.Height) -gt [int]$Dialog.Height) { throw 'MSI standard dialog control layout mismatch.' }
 }
}
