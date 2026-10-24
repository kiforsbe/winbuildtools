#requires -Version 7.4
<#
.SYNOPSIS
Verify native setup/servicing UI and shell registration without installing.
.DESCRIPTION
Real synthetic MSI databases exercise native tables and copied tamper cases.
No installation transaction, shortcut launch, trust import or application runs.
#>
$ErrorActionPreference='Stop'
$engine=Split-Path $PSScriptRoot -Parent
foreach($name in @('Configuration','Identity','Branding','Payload','Database','Registration','Maintenance','Scope','Presentation','Wizard','Semantics','Authoring','Inspection')) { if(Test-Path "$engine/$name.ps1") { . "$engine/$name.ps1" } }
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('WbtWizard-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path "$fixture/payload/Assets" -Force
$script:checks=0
function Check([bool]$Value,[string]$Message) { if(!$Value) { throw $Message };$script:checks++ }
try {
 $blocked=$null
 try { & "$engine/tests/acceptance.ps1" -OutputDirectory "$fixture/blocked-lifecycle" -RunLifecycle } catch { $blocked=$_ }
 Check ($blocked -and $blocked.ToString().Contains('-DisposableHost')) 'Lifecycle must reject absent explicit disposable-host opt-in.'
 Check (!(Test-Path -LiteralPath "$fixture/blocked-lifecycle")) 'Lifecycle guard must run before creating output or an installer transaction.'
 foreach($name in @('Example.exe','Assets/Example.ico')) { [IO.File]::WriteAllText("$fixture/payload/$name",'Synthetic fixture '+$name) }
 $config=Read-MsiConfiguration "$engine/example.json"
 foreach($arch in @('x64','ARM64')) {
  $path="$fixture/$arch.msi"
  New-MsiPackage $config "$fixture/payload" $path '1.2.3' $arch
  $info=Read-MsiPackage $path
  Check ('INSTALLFOLDER' -cin ($info.Properties.SecureCustomProperties -split ';')) 'Selected destination must survive restricted UI-to-server property transfer.'
  Check ('WBTACCEPTLICENSE' -cin ($info.Properties.SecureCustomProperties -split ';')) 'Full UI license acceptance must reach server launch conditions.'
  Check ('MsiShortcutProperty' -in $info.Tables) 'Start shortcuts need explicit native uninstall metadata.'
  $entry=@($info.SemanticTables.MsiShortcutProperty | Where-Object PropertyKey -CEQ 'System.AppUserModel.UninstallCommand')
  Check ($entry.Count -eq 1 -and $entry[0].Shortcut_ -ceq 'Shortcut1' -and $entry[0].PropVariantValue -ceq '"[System64Folder]msiexec.exe" /x [ProductCode]') 'Start uninstall invokes exact native product uninstall with visible UI.'
  $setLocation=@($info.SemanticTables.CustomAction | Where-Object Action -CEQ WbtSetInstallLocation)
  Check ($setLocation.Count -eq 1 -and $setLocation[0].Type -eq '51' -and $setLocation[0].Source -ceq 'ARPINSTALLLOCATION' -and $setLocation[0].Target -ceq '[INSTALLFOLDER]') 'ARP location is the resolved installation directory.'
  Check (@($info.Actions | Where-Object { $_.Action -ceq 'WbtSetInstallLocation' -and $_.Sequence -eq '1125' }).Count -eq 1) 'Registration setter follows costing and precedes registration.'
  $remembered=@($info.SemanticTables.Registry | Where-Object Registry -CEQ WbtRememberInstallFolder)
  Check ($remembered.Count -eq 1 -and $remembered[0].Root -eq '-1' -and $remembered[0].Name -ceq 'InstallLocation' -and $remembered[0].Value -ceq '[INSTALLFOLDER]') 'Native context-owned folder memory must preserve a customized directory on upgrade.'
  Assert-MsiContents $path "$fixture/payload" $config '1.2.3' $arch "$fixture/inspect-$arch"
  Check (!$info.Properties.ContainsKey('ARPNOMODIFY')) 'Windows maintenance entry must be available with a repair/remove wizard.'
  $ui=Read-MsiMaintenanceUi $path
  $wizard=Get-MsiWizardDefinition $config $arch
  Check (@($wizard.ControlCondition.Rows | Where-Object { $_[0] -ceq 'WbtProgress' -and $_[1] -ceq 'Cancel' -and $_[2] -ceq 'Disable' -and $_[3] -ceq 'UILevel < 5' }).Count -eq 1) 'Reduced UI must not offer a Cancel event that requires full UI.'
  Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq 'WbtProgress' -and $_.Event -ceq 'EndDialog' }).Count -eq 0) 'Do not publish unsupported reduced-UI EndDialog.'
  Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq 'WbtWelcome' -and $_.Event -ceq '[WBTINSTALLPATH]' -and $_.Argument -ceq '[INSTALLFOLDER]' -and $_.Condition -match 'NOT WBTINSTALLPATH' }).Count -eq 1) 'Full UI must honor an explicit destination without resetting it on Back.'
  foreach($dialog in @('WbtWelcome','WbtOptions','WbtReady','WbtMaintenance','WbtRemove','WbtRepair','WbtUpgrade','WbtProgress','WbtCancelConfirm')) {
   Check (@($ui.Dialogs | Where-Object Dialog -CEQ $dialog).Count -eq 1) "Native wizard page missing: $dialog"
  }
  Check (@($ui.EventMappings | Where-Object { $_.Dialog_ -ceq 'WbtProgress' -and $_.Control_ -ceq 'Progress' -and $_.Event -ceq 'SetProgress' -and $_.Attribute -ceq 'Progress' }).Count -eq 1) 'Progress must subscribe to actual native engine ticks.'
  Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq 'WbtMaintenance' -and $_.Event -ceq '[REINSTALL]' -and $_.Argument -ceq 'ALL' }).Count -eq 1) 'Repair must select installed features.'
  Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq 'WbtMaintenance' -and $_.Event -ceq '[REMOVE]' -and $_.Argument -ceq 'ALL' }).Count -eq 1) 'Remove must use standard MSI removal.'
  Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq 'WbtRepair' -and $_.Event -ceq 'Reinstall' -and $_.Argument -ceq 'ALL' }).Count -eq 1) 'Repair confirmation must update native feature action state after costing.'
  Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq 'WbtRemove' -and $_.Event -ceq 'Remove' -and $_.Argument -ceq 'ALL' }).Count -eq 1) 'Remove confirmation must update native feature action state after costing.'
  $welcome=@($ui.InstallUi | Where-Object Action -CEQ WbtWelcome)
  Check ($welcome.Count -eq 1 -and $welcome[0].Sequence -eq '5' -and $welcome[0].Condition -ceq 'NOT Installed AND UILevel = 5') 'Initial choices precede related-product discovery/costing and skip maintenance/silent UI.'
  Check (@($ui.InstallUi | Where-Object { $_.Action -ceq 'WbtRemove' -and $_.Condition -match 'NOT WBTMAINTENANCEUI' }).Count -eq 1) 'Remove selected in maintenance must not show confirmation twice.'
  $progress=@($ui.Dialogs | Where-Object Dialog -CEQ WbtProgress)[0]
  Check (($progress.Attributes -band 2) -eq 0) 'Progress must be modeless so the engine sequence can execute.'
  foreach($dialog in @($ui.Dialogs | Where-Object Dialog -Like 'Wbt*')) {
   $cycle=@($ui.Controls | Where-Object { $_.Dialog_ -ceq $dialog.Dialog -and $_.Control_Next })
   foreach($control in $cycle) {
    Check (@($cycle | Where-Object Control_Next -CEQ $control.Control).Count -eq 1) "Tab links must form closed cycles: $($dialog.Dialog).$($control.Control)"
   }
   foreach($control in @($ui.Controls | Where-Object Dialog_ -CEQ $dialog.Dialog)) {
    Check ([int]$control.X -ge 0 -and [int]$control.Y -ge 0 -and [int]$control.Width -gt 0 -and ([int]$control.Height -gt 0 -or $control.Type -eq 'Line') -and ([int]$control.X+[int]$control.Width) -le [int]$dialog.Width -and ([int]$control.Y+[int]$control.Height) -le [int]$dialog.Height) 'Every native control must fit its dialog.'
   }
  }
 }
 # Optional presentation fields must survive real MSI authoring/inspection too;
 # schema-only checks cannot catch native table/RTF/property-store mistakes.
 $presented=Read-MsiConfiguration "$engine/example.json"
 $presented.ui=@{allowDirectoryChange=$true;licenseText="Agreement {plain} \\ text`nUnicode å"}
 $presented.application.appUserModelId='Example.NativeInstaller'
 New-MsiPackage $presented "$fixture/payload" "$fixture/presentation.msi" '1.2.3' x64
 Assert-MsiContents "$fixture/presentation.msi" "$fixture/payload" $presented '1.2.3' x64 "$fixture/inspect-presentation"
 $presentation=Read-MsiPackage "$fixture/presentation.msi"
 Check (@($presentation.SemanticTables.MsiShortcutProperty | Where-Object { $_.PropertyKey -ceq 'System.AppUserModel.ID' -and $_.PropVariantValue -ceq 'Example.NativeInstaller' }).Count -eq 1) 'Optional app identity is consumer-owned and authored exactly.'
 $ui=Read-MsiMaintenanceUi "$fixture/presentation.msi"
 Check (@($ui.Controls | Where-Object { $_.Dialog_ -ceq 'WbtOptions' -and $_.Control -ceq 'Path' -and $_.Type -ceq 'PathEdit' }).Count -eq 1) 'Editable destination is opt-in and uses native path validation.'
 Check (@($ui.Controls | Where-Object { $_.Dialog_ -ceq 'WbtLicense' -and $_.Type -ceq 'ScrollableText' -and $_.Text -match '\\u229\?' -and $_.Text.Contains('\{plain\}') }).Count -eq 1) 'Plain license text must be escaped for native Unicode RTF.'
 $definition=Get-MsiWizardDefinition $presented x64
 Check (@($definition.ControlCondition.Rows | Where-Object { $_[0] -ceq 'WbtLicense' -and $_[2] -ceq 'Disable' -and $_[3] -ceq 'NOT (WBTACCEPTLICENSE = 1)' }).Count -eq 1) 'Only explicit acceptance enables Next.'
 $choice=Read-MsiConfiguration "$engine/example-v2.json"
 $scope=Get-MsiScopeDefinition $choice x64
 Check (@($scope.ControlEvent.Rows | Where-Object { $_[2] -ceq '[WBTINSTALLPATH]' -and $_[3] -ceq '[INSTALLFOLDER]' }).Count -eq 1) 'Scope chooser preserves an explicit initial destination.'
 Check (@($scope.ControlEvent.Rows | Where-Object { $_[2] -ceq '[WBTINSTALLPATH]' -and $_[4] -match 'WBTSELECTEDSCOPE <> WBTINSTALLSCOPE' }).Count -eq 2) 'Changing scope resets the destination; revisiting unchanged scope preserves edits.'
 # This is an actual copied package mutation, not a mock database reader.
 foreach($mutation in @(
  'UPDATE `CustomAction` SET `Type`=226 WHERE `Action`=''WbtSetInstallLocation''',
  'UPDATE `CustomAction` SET `Target`=''[SystemFolder]'' WHERE `Action`=''WbtSetInstallLocation''',
  'UPDATE `MsiShortcutProperty` SET `PropVariantValue`=''"[System64Folder]cmd.exe" /c exit''',
  'UPDATE `Control` SET `Width`=0 WHERE `Dialog_`=''WbtReady'' AND `Control`=''Next''',
  'DELETE FROM `EventMapping` WHERE `Control_`=''Progress''',
  'UPDATE `InstallUISequence` SET `Sequence`=900 WHERE `Action`=''WbtWelcome''',
  'UPDATE `ControlEvent` SET `Ordering`=99 WHERE `Dialog_`=''WbtReady'' AND `Event`=''[INSTALLFOLDER]''',
  'UPDATE `Registry` SET `Key`=''Software\WrongProduct''',
  'INSERT INTO `Dialog` (`Dialog`,`HCentering`,`VCentering`,`Width`,`Height`,`Attributes`,`Title`,`Control_First`,`Control_Default`,`Control_Cancel`) VALUES (''Unexpected'',50,50,400,290,3,''Unexpected'',''Next'',''Next'',''Next'')'
 )) {
  $tampered="$fixture/tampered-$checks.msi";Copy-Item "$fixture/x64.msi" $tampered
  $installer=$null;$db=$null
  try { $installer=New-Object -ComObject WindowsInstaller.Installer;$db=$installer.OpenDatabase($tampered,1);Invoke-MsiSql $db $mutation;$null=$db.Commit() } finally {Close-MsiCom $db;Close-MsiCom $installer}
  $before=(Get-FileHash $tampered).Hash;$failure=$null
  try { Assert-MsiContents $tampered "$fixture/payload" $config '1.2.3' x64 "$fixture/reject-$checks" } catch {$failure=$_}
  Check ($null -ne $failure) 'Unsafe registration mutation must fail.'
  Check (!(Test-Path "$fixture/reject-$checks")) 'Registration rejected before extraction.'
  Check ((Get-FileHash $tampered).Hash -ceq $before) 'Rejected registration inspection is read-only.'
 }
 Write-Host "Wizard/registration checks passed: $checks"
} finally {
 $target=[IO.Path]::GetFullPath($fixture)
 if([IO.Path]::GetDirectoryName($target) -ne [IO.Path]::GetTempPath().TrimEnd('\') -or [IO.Path]::GetFileName($target) -notlike 'WbtWizard-*') {throw 'Unsafe cleanup.'}
 Remove-Item -LiteralPath $target -Recurse -Force
}
