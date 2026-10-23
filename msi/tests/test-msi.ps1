#requires -Version 7.4

<#
.SYNOPSIS
Author and inspect standalone x64/ARM64 MSI fixtures without installing products.
.DESCRIPTION
Requires Windows Installer Automation, MakeCab and Expand. Checks tables, cabinet
bytes, identity stability/isolation and the public CLI from a copied msi/ folder.
Native costing runs only for the host architecture; lifecycle/ICE tests are separate.
#>
$ErrorActionPreference='Stop'
$engine=Split-Path $PSScriptRoot -Parent
foreach($name in @('Configuration','Identity','Payload','Database','Registration','Maintenance','Scope','Wizard','Semantics','Authoring','Inspection')) {
 if(Test-Path "$engine/$name.ps1") { . "$engine/$name.ps1" }
}
if(!(Get-Command New-MsiPackage -ErrorAction SilentlyContinue)) { throw 'Missing native MSI authoring.' }
$script:checks=0
function Check([bool]$Value,[string]$Message) { if(!$Value) { throw $Message }; $script:checks++ }
function Rejected([scriptblock]$Action) { $failed=$false; try { & $Action | Out-Null } catch { $failed=$true }; Check $failed 'Expected MSI rejection.' }
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('GenericMsi-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path "$fixture/payload/Assets" -Force
try {
 $config=Read-MsiConfiguration "$engine/example.json"
 foreach($name in @('Example.exe','Assets/Example.ico')) { [IO.File]::WriteAllText("$fixture/payload/$name",'Synthetic fixture '+$name) }
 $prior=@{}
 # Both architectures are authored on this host. Synthetic executable/icon bytes
 # are never launched; foreign-architecture success proves metadata and payload.
 foreach($arch in @('x64','ARM64')) {
  $path="$fixture/$arch.msi"
  New-MsiPackage $config "$fixture/payload" $path '0.1.0' $arch
  $info=Read-MsiPackage $path
  Check ($info.Properties.ProductName -ceq 'Example') 'Configured product name.'
  Check ($info.Template -ceq $(if($arch -eq 'x64'){'x64;1033'}else{'Arm64;1033'})) 'Native architecture.'
  Check ($info.CustomActionCount -eq 3 -and $info.RegistryCount -eq 1) 'Only exact declarative registration actions and context-owned folder memory.'
  Check ('Signature' -in $info.Tables) 'Required AppSearch table.'
  Check ($info.Files.Count -eq 2 -and $info.FeatureComponents.Count -eq 2) 'Payload feature membership.'
  Check ($info.Properties.ALLUSERS -eq '1') 'Machine install.'
  # Validate the authored policy without launching an install or asking Windows
  # to shut down a real application. Interactive/silent behavior needs lifecycle
  # acceptance on an explicitly approved disposable host.
  Check ($info.Properties.MSIRESTARTMANAGERCONTROL -ceq '0') 'Restart Manager must be enabled.'
  Check ($info.Properties.MSIRMSHUTDOWN -ceq '0') 'Restart Manager must not force termination.'
  Check ($info.Properties.MSIDISABLERMRESTART -ceq '1') 'Restart Manager must not relaunch applications.'
  Check ($info.Properties.REBOOT -ceq 'ReallySuppress') 'Automatic reboot remains suppressed.'
  Check ($info.Properties.ErrorDialog -ceq 'WbtError') 'Authored UI must display native errors.'
  Check (@('Dialog','Control','ControlEvent','ListBox','TextStyle' | Where-Object {$_ -notin $info.Tables}).Count -eq 0) 'Files-in-use UI tables must be authored.'
  $ui=Read-MsiMaintenanceUi $path
  Check (@($ui.Dialogs).Count -ge 15 -and @($ui.Controls).Count -gt 23 -and @($ui.Events).Count -gt 16) 'Full UI contains RM/legacy consent and standard error/termination dialogs.'
  $errorDialog=@($ui.Dialogs | Where-Object Dialog -CEQ 'WbtError')[0]
  Check (($errorDialog.Attributes -band 65536) -and $errorDialog.Control_First -ceq 'ErrorText') 'Native Error dialog style and text control.'
  Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq 'WbtError' -and $_.Event -ceq 'EndDialog' -and $_.Argument -in @('ErrorAbort','ErrorCancel','ErrorIgnore','ErrorNo','ErrorOk','ErrorRetry','ErrorYes') }).Count -eq 7) 'All seven standard error results are mapped.'
  Check (@($ui.Controls | Where-Object { $_.Dialog_ -ceq 'WbtError' -and $_.Control_Next }).Count -eq 0) 'Error dialog buttons must not form a tab cycle.'
  foreach($sequenceName in @('InstallUi','AdminUi')) {
   Check (@($ui.$sequenceName | Where-Object { [int]$_.Sequence -in @(-1,-2,-3) -and $_.Condition -ceq 'UILevel = 5' }).Count -eq 3) 'Native success/user-exit/failure result dialogs must be sequenced.'
  }
  foreach($dialogName in @('MsiRMFilesInUse','FilesInUse')) {
   $dialog=@($ui.Dialogs | Where-Object Dialog -CEQ $dialogName)[0]
   Check ($dialog.Control_Default -ceq 'Cancel' -and $dialog.Control_Cancel -ceq 'Cancel') 'Enter/Escape defaults must not close applications.'
   $processList=@($ui.Controls | Where-Object { $_.Dialog_ -ceq $dialogName -and $_.Control -ceq 'Processes' })[0]
   Check ($processList.Type -ceq 'ListBox' -and $processList.Property -ceq 'FileInUseProcess') 'Native process-list binding.'
   Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq $dialogName -and $_.Control_ -ceq 'Cancel' -and $_.Event -ceq 'EndDialog' -and $_.Argument -ceq 'Exit' -and $_.Condition -ceq '1' }).Count -eq 1) 'Cancel must exit setup.'
  }
  Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq 'MsiRMFilesInUse' -and $_.Control_ -ceq 'Close' -and $_.Event -ceq 'RMShutdownAndRestart' -and $_.Argument -ceq '0' -and $_.Ordering -eq '2' }).Count -eq 1) 'Only the explicit Close button requests native RM shutdown.'
  Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq 'FilesInUse' -and $_.Control_ -ceq 'Retry' -and $_.Event -ceq 'EndDialog' -and $_.Argument -ceq 'Retry' }).Count -eq 1) 'Legacy UI retries after manual closure.'
  Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq 'FilesInUse' -and $_.Control_ -ceq 'Ignore' -and $_.Event -ceq 'EndDialog' -and $_.Argument -ceq 'Ignore' }).Count -eq 1) 'Legacy UI has the standard explicit continue-without-closing result.'
  $installName=@($info.Directories | Where-Object Directory -eq 'INSTALLFOLDER')[0].DefaultDir
  Check (($installName -split '\|')[-1] -eq "Example ($($arch.ToLowerInvariant()))") 'Architecture directories cannot overwrite one another.'
  Check ($installName -match '^[A-Z0-9]{8}\|') 'Root directories carry valid short/long aliases.'
  Check ($info.Shortcuts[0].Name -match '^[A-Z0-9]{8}\|Example$') 'Shortcuts carry valid short/long aliases.'
  Check ($info.LaunchConditions -match '22000') 'Configured OS floor.'
  Check ($info.UpgradeCount -eq 2) 'Upgrade and downgrade rows.'
  $hash=(Get-FileHash $path).Hash
  Rejected { New-MsiPackage $config "$fixture/payload" $path '0.1.0' $arch }
  Check ((Get-FileHash $path).Hash -eq $hash) 'Repeated output never overwrites.'
  Assert-MsiContents $path "$fixture/payload" $config '0.1.0' $arch "$fixture/inspect-$arch"
  New-MsiPreflightCopy $path "$fixture/isolated-$arch.msi"
  $isolated=Read-MsiPackage "$fixture/isolated-$arch.msi"
  Check ($isolated.Properties.MSIRESTARTMANAGERCONTROL -ceq 'Disable' -and $info.Properties.MSIRESTARTMANAGERCONTROL -ceq '0') 'Preflight disables Restart Manager only in its isolated copy.'
  Check ($isolated.Properties.ProductCode -ne $info.Properties.ProductCode -and $isolated.Properties.UpgradeCode -ne $info.Properties.UpgradeCode) 'Preflight identity isolation.'
  Check ($isolated.PackageCode -ne $info.PackageCode) 'Preflight package isolation.'
  Check (@($isolated.Components | Where-Object ComponentId -in @($info.Components.ComponentId)).Count -eq 0) 'Preflight component isolation.'
  Check ((Get-FileHash $path).Hash -eq $hash) 'Inspection preserves original bytes.'
  $prior[$arch]=$info
 }
 Check ($prior.x64.Properties.UpgradeCode -ne $prior.ARM64.Properties.UpgradeCode) 'Architecture upgrade isolation.'
 # Mutate disposable database bytes rather than mocking the reader: inspection
 # must reject unsafe policy/UI before creating extraction evidence or running
 # native costing. The original deliverable remains unchanged throughout.
 function Reject-MaintenanceMutation([string]$Name,[string]$Sql,[string]$Pattern,[object[]]$ReplacementEvent=@()) {
  $tampered=Join-Path $fixture ("tampered-$Name.msi")
  Copy-Item -LiteralPath "$fixture/x64.msi" -Destination $tampered
  $installer=$null;$database=$null
  try {
   $installer=New-Object -ComObject WindowsInstaller.Installer
   $database=$installer.OpenDatabase($tampered,1)
   try { Invoke-MsiSql $database $Sql } catch { throw "Cannot create maintenance fixture '$Name': $_" }
   # MSI does not permit updating primary-key fields such as event arguments
   # and conditions in place. Replace those records through parameterized values.
   if($ReplacementEvent.Count) { Add-MsiRow $installer $database ControlEvent @('Dialog_','Control_','Event','Argument','Condition','Ordering') $ReplacementEvent }
   $null=$database.Commit()
  } finally { Close-MsiCom $database;Close-MsiCom $installer }
  $before=(Get-FileHash -LiteralPath $tampered).Hash
  $inspection=Join-Path $fixture ("rejected-$Name")
  $failure=$null
  try { Assert-MsiContents $tampered "$fixture/payload" $config '0.1.0' 'x64' $inspection } catch { $failure=$_ }
  Check ($null -ne $failure -and $failure.ToString() -match $Pattern) "Unsafe MSI maintenance mutation was accepted or rejected for the wrong reason: $Name ($failure)"
  Check (!(Test-Path -LiteralPath $inspection)) 'Unsafe maintenance policy rejected before payload extraction.'
  Check ((Get-FileHash -LiteralPath $tampered).Hash -ceq $before) 'Rejected inspection preserves tampered input bytes.'
 }
 Reject-MaintenanceMutation 'force' 'UPDATE `Property` SET `Value`=''1'' WHERE `Property`=''MSIRMSHUTDOWN''' 'maintenance policy'
 Reject-MaintenanceMutation 'disabled' 'UPDATE `Property` SET `Value`=''Disable'' WHERE `Property`=''MSIRESTARTMANAGERCONTROL''' 'maintenance policy'
 Reject-MaintenanceMutation 'restart' 'UPDATE `Property` SET `Value`=''0'' WHERE `Property`=''MSIDISABLERMRESTART''' 'maintenance policy'
 Reject-MaintenanceMutation 'reboot' 'DELETE FROM `Property` WHERE `Property`=''REBOOT''' 'maintenance policy'
 Reject-MaintenanceMutation 'font' 'DELETE FROM `Property` WHERE `Property`=''DefaultUIFont''' 'maintenance policy'
 Reject-MaintenanceMutation 'limited-ui' 'INSERT INTO `Property` (`Property`,`Value`) VALUES (''LIMITUI'',''1'')' 'maintenance policy'
 Reject-MaintenanceMutation 'missing-rm' 'DELETE FROM `Property` WHERE `Property`=''MSIRESTARTMANAGERCONTROL''' 'maintenance policy'
 # Even a direct copy-only preflight call must disable RM when its source omitted
 # the property. This check never opens the disposable MSI as an install session.
 New-MsiPreflightCopy "$fixture/tampered-missing-rm.msi" "$fixture/preflight-missing-rm.msi"
 $missingPolicyCopy=Read-MsiPackage "$fixture/preflight-missing-rm.msi"
 Check ($missingPolicyCopy.Properties.MSIRESTARTMANAGERCONTROL -ceq 'Disable') 'Preflight must insert its disabling policy if absent.'
 Reject-MaintenanceMutation 'dialog' 'DELETE FROM `Dialog` WHERE `Dialog`=''MsiRMFilesInUse''' 'files-in-use'
 Reject-MaintenanceMutation 'consent' 'DELETE FROM `ControlEvent` WHERE `Event`=''RMShutdownAndRestart''' 'files-in-use'
 Reject-MaintenanceMutation 'cancel' 'DELETE FROM `ControlEvent` WHERE `Dialog_`=''MsiRMFilesInUse'' AND `Control_`=''Cancel''' 'files-in-use' @('MsiRMFilesInUse','Cancel','EndDialog','Return','1',1)
 Reject-MaintenanceMutation 'condition' 'DELETE FROM `ControlEvent` WHERE `Event`=''RMShutdownAndRestart''' 'files-in-use' @('MsiRMFilesInUse','Close','RMShutdownAndRestart','0','0',2)
 Reject-MaintenanceMutation 'binding' 'UPDATE `Control` SET `Property`=''WrongList'' WHERE `Control`=''Processes''' 'files-in-use'
 Reject-MaintenanceMutation 'disabled-button' 'UPDATE `Control` SET `Attributes`=1 WHERE `Control`=''Close''' 'files-in-use'
 Reject-MaintenanceMutation 'default-close' 'UPDATE `Dialog` SET `Control_Default`=''Close'' WHERE `Dialog`=''MsiRMFilesInUse''' 'files-in-use'
 Reject-MaintenanceMutation 'clipped-button' 'UPDATE `Control` SET `Width`=0 WHERE `Control`=''Close''' 'files-in-use'
 Reject-MaintenanceMutation 'error-property' 'DELETE FROM `Property` WHERE `Property`=''ErrorDialog''' 'maintenance policy'
 Reject-MaintenanceMutation 'error-style' 'UPDATE `Dialog` SET `Attributes`=3 WHERE `Dialog`=''WbtError''' 'standard error'
 Reject-MaintenanceMutation 'error-tab' 'UPDATE `Control` SET `Control_Next`=''C'' WHERE `Dialog_`=''WbtError'' AND `Control`=''O''' 'standard error'
 Reject-MaintenanceMutation 'error-result' 'DELETE FROM `ControlEvent` WHERE `Dialog_`=''WbtError'' AND `Control_`=''O''' 'standard error' @('WbtError','O','EndDialog','Return','1',1)
 Reject-MaintenanceMutation 'termination' 'DELETE FROM `InstallUISequence` WHERE `Sequence`=-2' 'standard termination|wizard'
 Reject-MaintenanceMutation 'admin-termination' 'DELETE FROM `AdminUISequence` WHERE `Sequence`=-3' 'standard termination|wizard'
 Reject-MaintenanceMutation 'error-text-layout' 'UPDATE `Control` SET `Width`=0 WHERE `Dialog_`=''WbtError'' AND `Control`=''ErrorText''' 'standard.*layout|wizard'
 Reject-MaintenanceMutation 'termination-layout' 'UPDATE `Control` SET `Width`=0 WHERE `Dialog_`=''WbtUserExit'' AND `Control`=''Finish''' 'standard.*layout|wizard'
 # A version bump changes product identity while retaining upgrade/component
 # identity; a different product namespace below must change both families.
 New-MsiPackage $config "$fixture/payload" "$fixture/new.msi" '0.2.0' 'x64'
 $new=Read-MsiPackage "$fixture/new.msi"
 Check ($new.Properties.ProductCode -ne $prior.x64.Properties.ProductCode) 'Version changes product code.'
 Check ($new.Properties.UpgradeCode -eq $prior.x64.Properties.UpgradeCode) 'Upgrade identity stable.'
 Check ($new.Components[0].ComponentId -eq $prior.x64.Components[0].ComponentId) 'Component identity stable across versions.'
 # Reject even an empty custom-action table before opening a native session.
 Copy-Item "$fixture/x64.msi" "$fixture/blocked.msi"
 $installer=$null; $database=$null
 try {
  $installer=New-Object -ComObject WindowsInstaller.Installer
  $database=$installer.OpenDatabase("$fixture/blocked.msi",1)
  Invoke-MsiSql $database 'DROP TABLE `CustomAction`'
  Invoke-MsiSql $database 'CREATE TABLE `CustomAction` (`Action` CHAR(72) NOT NULL PRIMARY KEY `Action`)'
  $null=$database.Commit()
 } finally { Close-MsiCom $database; Close-MsiCom $installer }
 $before=(Get-FileHash "$fixture/blocked.msi").Hash
 Rejected { Assert-MsiPreflight "$fixture/blocked.msi" }
 Check ((Get-FileHash "$fixture/blocked.msi").Hash -eq $before) 'Rejected preflight never changes original bytes.'
 $config.product.upgradeCode=[guid]::NewGuid().ToString('B'); $config.product.name='Second Product'; $config.product.id='second'
 New-MsiPackage $config "$fixture/payload" "$fixture/second.msi" '0.1.0' 'x64'
 $second=Read-MsiPackage "$fixture/second.msi"
 Check ($second.Properties.UpgradeCode -ne $prior.x64.Properties.UpgradeCode -and $second.Components[0].ComponentId -ne $prior.x64.Components[0].ComponentId) 'Product identity isolation.'
 # Copy only the engine outside the repository and invoke its public command.
 Copy-Item -LiteralPath $engine -Destination "$fixture/standalone engine" -Recurse
 $config | ConvertTo-Json -Depth 10 | Set-Content "$fixture/second.json"
 Push-Location $fixture
 try {
  $result=& './standalone engine/package.ps1' -Config './second.json' -PayloadDirectory './payload' -Version '0.3.0' -Architecture x64 -OutputDirectory './public output'
 } finally { Pop-Location }
 Check (Test-Path $result.Artifact) 'Standalone public command works.'
 Check ($result.SHA256 -eq (Get-FileHash $result.Artifact).Hash) 'Public result identifies final bytes.'
 Write-Host "Native MSI checks passed: $checks (synthetic files; no product installed)."
} finally {
 $target=[IO.Path]::GetFullPath($fixture)
 if([IO.Path]::GetDirectoryName($target) -ne [IO.Path]::GetTempPath().TrimEnd('\') -or [IO.Path]::GetFileName($target) -notlike 'GenericMsi-*') { throw 'Unsafe MSI test cleanup.' }
 Remove-Item -LiteralPath $target -Recurse -Force
}
