#requires -Version 7.4
<#
.SYNOPSIS
Exercise configurable native presentation, image bytes and bounded UI actions.
.DESCRIPTION
Synthetic x64/ARM64 packages and copied mutations only. Native UI is inspected,
never navigated, linked or launched. No product is installed or application run.
#>
$ErrorActionPreference='Stop'
$engine=Split-Path $PSScriptRoot -Parent
foreach($name in @('Configuration','Identity','Branding','Payload','Database','Registration','Maintenance','Scope','Presentation','Wizard','Semantics','Authoring','Inspection')) { if(Test-Path "$engine/$name.ps1") { . "$engine/$name.ps1" } }
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('WbtPresentation-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path "$fixture/payload/Assets" -Force
$script:checks=0
function Check([bool]$Value,[string]$Message) { if(!$Value) { throw $Message };$script:checks++ }
try {
 [IO.File]::WriteAllText("$fixture/payload/Example.exe",'Inert application fixture')
 Add-Type -AssemblyName System.Drawing
 $bitmap=[Drawing.Bitmap]::new(48,48)
 try { $bitmap.SetPixel(0,0,[Drawing.Color]::Blue);$bitmap.Save("$fixture/payload/Assets/logo.png",[Drawing.Imaging.ImageFormat]::Png) } finally {$bitmap.Dispose()}
 foreach($case in @(@(1,'x64','brandedSidebar'),@(2,'x64','compactHeader'),@(2,'ARM64','brandedSidebar'),@(1,'ARM64','compactHeader'))) {
  $schema,$arch,$layout=$case
  $cfg=Read-MsiConfiguration $(if($schema -eq 1){"$engine/example.json"}else{"$engine/example-v2.json"})
  $cfg.application=@{executable='Example.exe'}
  $cfg.payload=@{requiredFiles=@('Example.exe');allowedExtensions=@('.exe','.png');allowedFiles=@()}
  $cfg.ui=@{layout=$layout;logo='Assets/logo.png';allowDirectoryChange=$true;showBrowseButton=$true;completion=@{launchApplication=$true;showDetails=$true;releaseNotesUrl='https://example.com/notes?a=1&b=2';helpUrl='https://example.com/help';messages=@{installed='Ready [literal] & {text}.';updated='Updated.';repaired='Repaired.';removed='Removed.';restartRequired='Restart Windows.'}}}
  if($layout -eq 'brandedSidebar') { $cfg.ui.sidebarImage='Assets/logo.png' }
  if($schema -eq 2) { $cfg.architecture=$arch;$cfg.components=@{'Example.exe'=[guid]::NewGuid().ToString('B');'Assets/logo.png'=[guid]::NewGuid().ToString('B')} }
  $cfg | ConvertTo-Json -Depth 15 | Set-Content "$fixture/config.json"
  $cfg=Read-MsiConfiguration "$fixture/config.json"
  $path="$fixture/$schema-$arch.msi"
  New-MsiPackage $cfg "$fixture/payload" $path '1.2.3' $arch
  $info=Read-MsiPackage $path
  Check ('Binary' -in $info.Tables) 'Configured wizard images need native Binary resources.'
  Check ((Get-MsiBrandingHash $path WbtUiLogo) -ceq (Get-FileHash "$fixture/payload/Assets/logo.png").Hash) 'Embedded logo bytes must match approved image.'
  Assert-MsiContents $path "$fixture/payload" $cfg '1.2.3' $arch "$fixture/inspect-$schema-$arch"
  $ui=Read-MsiMaintenanceUi $path
  $message=@($ui.Controls | Where-Object { $_.Dialog_ -ceq 'WbtExit' -and $_.Control -ceq 'MessageInstalled' })[0]
  Check (([int]$message.Attributes -band 131072) -ne 0) 'Plain completion text must preserve literal ampersands, not access-key mnemonics.'
  Check ($message.Text.Contains('Ready [\[]literal[\]] & {text}.')) 'MSI brackets and ordinary punctuation stay literal in consumer messages.'
  foreach($dialog in @('WbtBrowse','WbtInstallDetails')) { Check (@($ui.Dialogs | Where-Object Dialog -CEQ $dialog).Count -eq 1) "Missing native convenience dialog: $dialog" }
  Check (@($ui.Controls | Where-Object { $_.Dialog_ -ceq 'WbtOptions' -and $_.Control -ceq 'HeaderLogo' -and $_.Type -ceq 'Bitmap' }).Count -eq 1) 'Other pages show small configured logo.'
  $resource=if($layout -eq 'brandedSidebar') {'SidebarImage'}else{'HeaderLogo'}
  Check (@($ui.Controls | Where-Object { $_.Dialog_ -ceq 'WbtExit' -and $_.Control -ceq $resource }).Count -eq 1) 'Completion must use the selected layout.'
  Check (@($ui.Controls | Where-Object { $_.Dialog_ -ceq 'WbtExit' -and $_.Type -ceq 'Hyperlink' -and $_.Text.Contains('&amp;') }).Count -eq 1) 'HTTPS links are escaped without losing query separators.'
  $launch=@($ui.Events | Where-Object Event -CEQ MsiLaunchApp)
  $file=@($info.SemanticTables.File | Where-Object FileName -Match 'Example.exe')[0]
  Check ($launch.Count -eq 1 -and $launch[0].Argument -ceq ('"[#'+$file.File+']"')) 'Launch is exact installed executable identity, without arbitrary command arguments.'
  foreach($condition in @('UILevel = 5','WBTLAUNCHAPP = 1','NOT Installed','NOT REMOVE','NOT REINSTALL','NOT MsiSystemRebootPending','NOT ReplacedInUseFiles')) { Check ($launch[0].Condition.Contains($condition)) "Launch gating must include $condition" }
  Check (!$info.Properties.ContainsKey('WBTLAUNCHAPP')) 'Launch choice is initially unchecked.'
  Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq 'WbtBrowse' -and $_.Event -ceq 'CheckTargetPath' -and $_.Ordering -eq '1' }).Count -eq 1) 'Browse validates before committing the selection.'
  Check (@($ui.Events | Where-Object { $_.Dialog_ -ceq 'WbtBrowse' -and $_.Control_ -ceq 'Cancel' -and $_.Event -ceq '[WBTINSTALLPATH]' }).Count -eq 0) 'Browse Cancel must not change original destination.'
  Check (@($ui.Events | Where-Object Event -CEQ DirectoryListNew).Count -eq 0) 'Browse must not create directories before installation confirmation.'
  Check (@($ui.Controls | Where-Object { $_.Dialog_ -ceq 'WbtExit' -and $_.Control -like 'Heading*' }).Count -ge 4) 'Success text must distinguish install, update, repair and removal.'
  foreach($dialog in @($ui.Dialogs | Where-Object Dialog -Like 'Wbt*')) {
   $controls=@($ui.Controls | Where-Object Dialog_ -CEQ $dialog.Dialog)
   $cycle=@($controls | Where-Object Control_Next)
   foreach($control in $cycle) { Check (@($cycle | Where-Object Control_Next -CEQ $control.Control).Count -eq 1) "Closed native tab cycle: $($dialog.Dialog).$($control.Control)" }
   foreach($control in $controls) { Check ([int]$control.Width -gt 0 -and [int]$control.X -ge 0 -and [int]$control.Y -ge 0 -and ([int]$control.X+[int]$control.Width) -le [int]$dialog.Width -and ([int]$control.Y+[int]$control.Height) -le [int]$dialog.Height) 'Presentation controls fit dialog bounds.' }
  }
  if($arch -eq 'x64' -and $schema -eq 2) { $tamperSource=$path;$tamperConfig=$cfg }
 }
 foreach($mutation in @('launch','link','resource-name','resource-bytes')) {
  $tampered="$fixture/tampered-$checks.msi";Copy-Item $tamperSource $tampered
  $installer=$null;$db=$null
  try {
   $installer=New-Object -ComObject WindowsInstaller.Installer;$db=$installer.OpenDatabase($tampered,1)
   # MSI does not allow primary-key UPDATE. Replace the affected native row,
   # retaining every other field, so rejection tests exercise actual mutations.
   switch($mutation) {
    launch {
     $columns=@('Dialog_','Control_','Event','Argument','Condition','Ordering')
     $row=@(Get-MsiRows $db ControlEvent $columns | Where-Object Event -CEQ MsiLaunchApp)[0]
     Invoke-MsiSql $db 'DELETE FROM `ControlEvent` WHERE `Event`=''MsiLaunchApp'''
     Add-MsiRow $installer $db ControlEvent $columns @($row.Dialog_,$row.Control_,$row.Event,'cmd.exe',$row.Condition,[int]$row.Ordering)
    }
    link {Invoke-MsiSql $db 'UPDATE `Control` SET `Text`=''<a href="file:///C:/Windows/cmd.exe">Help</a>'' WHERE `Control`=''HelpLink'''}
    resource-name {
     Invoke-MsiSql $db 'DELETE FROM `Binary` WHERE `Name`=''WbtUiLogo'''
     Add-MsiRow $installer $db Binary @('Name','Data') @('Unexpected',"$fixture/payload/Assets/logo.png") @(1)
    }
    resource-bytes {
     Invoke-MsiSql $db 'DELETE FROM `Binary` WHERE `Name`=''WbtUiLogo'''
     [IO.File]::WriteAllText("$fixture/wrong-image.bin",'Changed binary bytes')
     Add-MsiRow $installer $db Binary @('Name','Data') @('WbtUiLogo',"$fixture/wrong-image.bin") @(1)
    }
   }
   $null=$db.Commit()
  } catch{throw "Fixture mutation failed: $mutation : $_"}finally{Close-MsiCom $db;Close-MsiCom $installer}
  $failure=$null;try {Assert-MsiContents $tampered "$fixture/payload" $tamperConfig '1.2.3' x64 "$fixture/reject-$checks"}catch{$failure=$_}
  Check ($null -ne $failure) 'Changed resource/link/launch action must be rejected.'
  Check (!(Test-Path "$fixture/reject-$checks")) 'Reject presentation mutation before extraction.'
 }
 $optout=$tamperConfig | ConvertTo-Json -Depth 15 | ConvertFrom-Json -AsHashtable
 $optout.ui.showBrowseButton=$false
 $optout.ui.completion=@{launchApplication=$false;showDetails=$false}
 New-MsiPackage $optout "$fixture/payload" "$fixture/optout.msi" '1.2.3' x64
 Assert-MsiContents "$fixture/optout.msi" "$fixture/payload" $optout '1.2.3' x64 "$fixture/inspect-optout"
 $off=Read-MsiMaintenanceUi "$fixture/optout.msi"
 Check (@($off.Dialogs | Where-Object Dialog -In @('WbtBrowse','WbtInstallDetails')).Count -eq 0) 'Disabled conveniences must not author dead dialogs.'
 Check (@($off.Events | Where-Object Event -CEQ MsiLaunchApp).Count -eq 0) 'Disabled launch must author no launch event.'
 Check (@($off.Controls | Where-Object Type -CEQ Hyperlink).Count -eq 0) 'Omitted links must author no hyperlink controls.'
 Check (@($off.Controls | Where-Object { $_.Dialog_ -ceq 'WbtOptions' -and $_.Control -ceq 'Path' -and $_.Type -ceq 'Edit' }).Count -eq 1) 'Browse can be disabled while retaining manual path editing.'
 Check (@($off.Controls | Where-Object { $_.Dialog_ -ceq 'WbtFatalError' -and $_.Control -ceq 'Log' }).Count -eq 1) 'Disabling optional details must retain failure diagnostics.'
 # Evaluate the launch gate with the real condition engine on an isolated copy.
 # No DoAction or UI navigation occurs: this only changes in-memory properties.
 New-MsiPreflightCopy $tamperSource "$fixture/conditions.msi"
 $installer=$null;$session=$null;$previousUi=$null
 try {
  $installer=New-Object -ComObject WindowsInstaller.Installer;$previousUi=$installer.UILevel;$installer.UILevel=2
  $session=$installer.OpenPackage([IO.Path]::GetFullPath("$fixture/conditions.msi"),0)
  $condition=@((Read-MsiMaintenanceUi $tamperSource).Events | Where-Object Event -CEQ MsiLaunchApp)[0].Condition
  foreach($case in @(@('allowed','',1),@('WBTLAUNCHAPP','',0),@('Installed','1',0),@('REMOVE','ALL',0),@('REINSTALL','ALL',0),@('UILevel','2',0),@('UILevel','3',0),@('UILevel','4',0),@('MsiSystemRebootPending','1',0),@('ReplacedInUseFiles','1',0))) {
   foreach($property in @('Installed','REMOVE','REINSTALL','MsiSystemRebootPending','ReplacedInUseFiles')){$session.Property($property)=''}
   $session.Property('UILevel')='5';$session.Property('WBTLAUNCHAPP')='1'
   if($case[0] -ne 'allowed'){$session.Property($case[0])=$case[1]}
   Check ($session.EvaluateCondition($condition) -eq $case[2]) "Native launch condition: $($case[0])=$($case[1])"
  }
 } finally {Close-MsiCom $session;if($installer -and $null -ne $previousUi){$installer.UILevel=$previousUi};Close-MsiCom $installer}
 # Corrupt or oversize sources fail before authoring. Keep file membership and
 # component maps unchanged so each rejection identifies the image boundary.
 $logoPath="$fixture/payload/Assets/logo.png";$original=[IO.File]::ReadAllBytes($logoPath)
 foreach($kind in @('malformed','oversize','dimensions','wrong-format')) {
  try {
   switch($kind) {
    malformed {[IO.File]::WriteAllText($logoPath,'Not an image')}
    oversize {[IO.File]::WriteAllBytes($logoPath,[byte[]]::new(8MB+1))}
    dimensions {
     $image=[Drawing.Bitmap]::new(2049,1)
     try {$image.Save($logoPath,[Drawing.Imaging.ImageFormat]::Png)}finally{$image.Dispose()}
    }
    wrong-format {
     $image=[Drawing.Bitmap]::new(8,8)
     try {$image.Save($logoPath,[Drawing.Imaging.ImageFormat]::Jpeg)}finally{$image.Dispose()}
    }
   }
   $failure=$null;try {Get-MsiPayload $optout "$fixture/payload" x64 | Out-Null}catch{$failure=$_}
   Check ($null -ne $failure) "Image source must be rejected: $kind"
  } finally {[IO.File]::WriteAllBytes($logoPath,$original)}
 }
 foreach($format in @('jpg','bmp','ico')) {
  $path="$fixture/format.$format"
  if($format -eq 'ico') {
   $icon=([Drawing.SystemIcons]::Application).Clone();$stream=[IO.File]::Create($path)
   try{$icon.Save($stream)}finally{$stream.Dispose();$icon.Dispose()}
  } else {
   $image=[Drawing.Bitmap]::new(8,8)
   try{$image.Save($path,$(if($format -eq 'jpg'){[Drawing.Imaging.ImageFormat]::Jpeg}else{[Drawing.Imaging.ImageFormat]::Bmp}))}finally{$image.Dispose()}
  }
  Assert-MsiBrandingAssets @{ui=@{logo="format.$format"}} $fixture
  Check ($true) "Supported image format decoded: $format"
 }
 Write-Host "Presentation checks passed: $checks"
} finally {
 $target=[IO.Path]::GetFullPath($fixture)
 if([IO.Path]::GetDirectoryName($target) -ne [IO.Path]::GetTempPath().TrimEnd('\') -or [IO.Path]::GetFileName($target) -notlike 'WbtPresentation-*') {throw 'Unsafe cleanup.'}
 Remove-Item -LiteralPath $target -Recurse -Force
}
