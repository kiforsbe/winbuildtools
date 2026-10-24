#requires -Version 7.4
<#
.SYNOPSIS
Apply consumer-selected branding and completion conveniences to the native model.
.DESCRIPTION
Called by Wizard after its core rows exist; Scope uses the small header helper.
Only native controls/events are added. Browse edits a temporary property before
costing and commits only after validation. Launch is an unchecked full-UI success
choice bound to the configured File key, without parameters or custom actions.
Images/links are explicit consumer data; inspection compares the resulting model.
#>
function Add-MsiScopeBranding($Model,$Configuration) {
 $logo=@(Get-MsiBrandingSpecs $Configuration | Where-Object Name -CEQ WbtUiLogo)
 if(!$logo.Count) { return }
 foreach($row in $Model.Control.Rows) {if($row[1] -in @('Message','Subtitle')){$row[5]=300}}
 $Model.Control.Rows+=,@('WbtScope','HeaderLogo',$logo[0].Kind,340,16,40,40,1,$null,'WbtUiLogo',$null)
}
function Update-MsiPresentationModel($Model,$Configuration,[string]$Architecture) {
 $ui=if($Configuration.ui){$Configuration.ui}else{@{}}
 $completion=if($ui.completion){$ui.completion}else{@{}}
 $messages=if($completion.messages){$completion.messages}else{@{}}
 $sidebar=$ui.layout -ceq 'brandedSidebar'
 $details=!$completion.ContainsKey('showDetails') -or $completion.showDetails
 function Row([string]$Table,[object[]]$Values) { $Model[$Table].Rows.Add($Values) }
 function Control([string]$Dialog,[string]$Name,[string]$Type,[int]$X,[int]$Y,[int]$Width,[int]$Height,[int]$Attributes,[object]$Property,[object]$Text) {
  # Text is descriptive plain content, not a keyboard mnemonic. Preserve literal
  # ampersands, including those in configured completion messages/product names.
  if($Type -ceq 'Text') {$Attributes=$Attributes -bor 131072}
  Row Control @($Dialog,$Name,$Type,$X,$Y,$Width,$Height,$Attributes,$Property,$Text,$null,$null)
 }
 function Event([string]$Dialog,[string]$Button,[string]$Name,[string]$Argument,[string]$Condition='1',[int]$Order=1) {Row ControlEvent @($Dialog,$Button,$Name,$Argument,$Condition,$Order)}
 function Visibility([string]$Dialog,[string]$Control,[string]$Condition) {
  Row ControlCondition @($Dialog,$Control,'Show',$Condition)
  Row ControlCondition @($Dialog,$Control,'Hide',('NOT ('+$Condition+')'))
 }
 function Message([string]$Name,[string]$Default) {
  # Fix the style prefix before consumer data so a leading {\Style} is displayed
  # literally instead of selecting a consumer-provided MSI font/style name.
  if($messages[$Name]) {return '{\WbtUIFont}'+(ConvertTo-MsiFormattedLiteral $messages[$Name])}
  return $Default
 }
 function RemoveControl([string]$Dialog,[string[]]$Names) {
  foreach($table in @('Control','ControlCondition','ControlEvent')) {
   foreach($row in @($Model[$table].Rows | Where-Object {$_[0] -ceq $Dialog -and $_[1] -in $Names})) {[void]$Model[$table].Rows.Remove($row)}
  }
 }
 function Cycle([string]$Dialog,[string[]]$Names) {
  for($i=0;$i -lt $Names.Count;$i++) {
   $row=@($Model.Control.Rows | Where-Object {$_[0] -ceq $Dialog -and $_[1] -ceq $Names[$i]})[0]
   $row[10]=$Names[($i+1)%$Names.Count]
  }
 }
 function SimplePage([string]$Name,[string]$Title,[string]$Description,[string]$First,[string]$Default,[string]$Cancel) {
  Row Dialog @($Name,50,50,400,290,3,'[ProductName] Setup',$First,$Default,$Cancel)
  Control $Name Heading Text 20 16 360 24 3 $null ('{\WbtHeading}'+$Title)
  Control $Name Subtitle Text 20 44 360 32 3 $null $Description
  Control $Name HeaderLine Line 0 78 400 0 1 $null $null
  Control $Name FooterLine Line 0 242 400 0 1 $null $null
  Control $Name Publisher Text 20 260 115 18 3 $null '[Manufacturer]'
 }
 function Sidebar([string]$Dialog) {
  RemoveControl $Dialog @('HeaderLine')
  if($ui.sidebarImage) {Control $Dialog SidebarImage Bitmap 0 0 120 242 1 $null WbtUiSidebar}
  else {
   Control $Dialog SidebarLine Line 120 0 1 242 1 $null $null
   if($ui.logo) {
    $kind=if([IO.Path]::GetExtension($ui.logo) -ieq '.ico'){'Icon'}else{'Bitmap'}
    Control $Dialog SidebarLogo $kind 30 40 60 60 1 $null WbtUiLogo
   }
   # Opaque native text preserves system/high-contrast colors. Consumer sidebar
   # artwork contains its own lettering; never place transparent text over it.
   Control $Dialog BrandName Text 14 116 92 65 3 $null '[ProductName]'
  }
 }
 if($ui.allowDirectoryChange -and (!$ui.ContainsKey('showBrowseButton') -or $ui.showBrowseButton)) {
  $path=@($Model.Control.Rows | Where-Object {$_[0] -ceq 'WbtOptions' -and $_[1] -ceq 'Path'})[0]
  $path[2]='PathEdit';$path[5]=270
  Control WbtOptions Browse PushButton 300 118 80 26 3 $null '&Browse...'
  Event WbtOptions Browse '[WBTBROWSEPATH]' '[WBTINSTALLPATH]' '1' 1
  Event WbtOptions Browse SpawnDialog WbtBrowse '1' 2
  Event WbtOptions Next CheckTargetPath WBTINSTALLPATH '1' 0
  Cycle WbtOptions @('Path','Browse','Back','Next','Cancel')
  SimplePage WbtBrowse 'Choose a destination folder' 'Choose an existing folder or enter a new destination path.' Path OK Cancel
  Control WbtBrowse Path PathEdit 20 92 360 22 3 WBTBROWSEPATH $null
  Control WbtBrowse Folders DirectoryList 20 124 360 100 7 WBTBROWSEPATH 'Destination folders'
  Control WbtBrowse Up PushButton 144 254 74 23 3 $null '&Up'
  Control WbtBrowse OK PushButton 226 254 74 23 3 $null '&OK'
  Control WbtBrowse Cancel PushButton 308 254 74 23 3 $null 'Cancel'
  Event WbtBrowse Up DirectoryListUp 0
  Row EventMapping @('WbtBrowse','Folders','DirectoryListUp','DirectoryListUp')
  Event WbtBrowse OK CheckTargetPath WBTBROWSEPATH '1' 1
  Event WbtBrowse OK '[WBTINSTALLPATH]' '[WBTBROWSEPATH]' '1' 2
  Event WbtBrowse OK EndDialog Return '1' 3
  Event WbtBrowse Cancel EndDialog Return
  Cycle WbtBrowse @('Path','Folders','Up','OK','Cancel')
 }
 # Diagnostic details are shared by result pages. The path/log fields are native
 # read-only edits so long values can be selected/copied without launching tools.
 if($details) {
  SimplePage WbtInstallDetails 'Installation details' 'Use the setup log when checking the installation result.' Location Close Close
  Control WbtInstallDetails Version Text 20 90 360 18 3 $null ('Version: [ProductVersion]    Architecture: '+$Architecture)
  Control WbtInstallDetails UserScope Text 20 111 360 18 2 $null 'Installation context: current user'
  Control WbtInstallDetails MachineScope Text 20 111 360 18 2 $null 'Installation context: all users'
  Visibility WbtInstallDetails UserScope 'NOT ALLUSERS OR (ALLUSERS = 2 AND MSIINSTALLPERUSER = 1)'
  Visibility WbtInstallDetails MachineScope 'ALLUSERS = 1 OR (ALLUSERS = 2 AND NOT MSIINSTALLPERUSER)'
  Control WbtInstallDetails LocationLabel Text 20 134 360 16 3 $null 'Installation folder:'
  Control WbtInstallDetails Location Edit 20 152 360 23 131075 INSTALLFOLDER $null
  Control WbtInstallDetails LogLabel Text 20 180 360 16 3 $null 'Setup log:'
  Control WbtInstallDetails Log Edit 20 199 360 23 131075 MsiLogFileLocation $null
  Control WbtInstallDetails Close PushButton 308 254 74 23 3 $null '&Close'
  Event WbtInstallDetails Close EndDialog Return
  Cycle WbtInstallDetails @('Location','Log','Close')
 }
 $restart='MsiSystemRebootPending OR ReplacedInUseFiles'
 $offer='UILevel = 5 AND NOT Installed AND NOT REMOVE AND NOT REINSTALL AND NOT MsiSystemRebootPending AND NOT ReplacedInUseFiles'
 $states=@(
  @('Installed','NOT REMOVE AND NOT REINSTALL AND NOT Installed AND NOT OLDERVERSIONS','[ProductName] was installed successfully',(Message installed 'Find [ProductName] in your Start menu. You can start using it right away.')),
  @('Updated','NOT REMOVE AND NOT REINSTALL AND NOT Installed AND OLDERVERSIONS','[ProductName] is up to date',(Message updated 'The new version is installed. Your personal application data has been kept.')),
  @('Repaired','NOT REMOVE AND (Installed OR REINSTALL)','[ProductName] was repaired successfully',(Message repaired 'Application files and shortcuts have been restored.')),
  @('Removed','REMOVE~="ALL"','[ProductName] was removed',(Message removed 'The application and its shortcuts have been removed. Personal application data has been kept.'))
 )
 foreach($dialog in @('WbtExit','WbtUserExit','WbtFatalError')) {
  RemoveControl $dialog @('Heading','Subtitle','Message','Log','Restart')
  $x=if($sidebar){140}else{20};$width=if($sidebar){240}else{360}
  $headingY=if($sidebar){25}else{16};$headingH=if($sidebar){55}else{54}
  $messageY=if($sidebar){87}else{94}
  if($sidebar){Sidebar $dialog}
  if($dialog -ceq 'WbtExit') {
   foreach($state in $states) {
    $attributes=if($state[0] -ceq 'Installed'){3}else{2}
    Control $dialog ('Heading'+$state[0]) Text $x $headingY $width $headingH $attributes $null ('{\WbtHeading}'+$state[2])
    Visibility $dialog ('Heading'+$state[0]) $state[1]
    Control $dialog ('Message'+$state[0]) Text $x $messageY $width 60 $attributes $null $state[3]
    Visibility $dialog ('Message'+$state[0]) ('('+$state[1]+') AND NOT ('+$restart+')')
   }
   Control $dialog Restart Text $x $messageY $width 60 2 $null (Message restartRequired 'Windows may require a restart to finish applying changes. Review the setup log and installation result.')
   Visibility $dialog Restart $restart
  } else {
   $heading=if($dialog -ceq 'WbtUserExit'){'[ProductName] setup was canceled'}else{'[ProductName] setup could not complete'}
   $message=if($dialog -ceq 'WbtUserExit'){Message canceled 'The operation did not complete. Review the setup log if recovery or a restart is needed.'}else{Message failed 'An error prevented setup from finishing. Review the setup log before trying again.'}
   Control $dialog Heading Text $x $headingY $width $headingH 3 $null ('{\WbtHeading}'+$heading)
   Control $dialog Message Text $x $messageY $width 58 3 $null $message
   Control $dialog Log Text $x 158 $width 48 2 $null 'Setup log: [MsiLogFileLocation]'
   Visibility $dialog Log MsiLogFileLocation
  }
  $cycle=[Collections.Generic.List[string]]::new();$cycle.Add('Finish')
  if($dialog -ceq 'WbtExit') {
   if($completion.launchApplication) {
    Control $dialog Launch CheckBox $x 157 $width 30 3 WBTLAUNCHAPP 'Run [ProductName] when I click Finish'
    Row CheckBox @('WBTLAUNCHAPP','1');Visibility $dialog Launch $offer;$cycle.Add('Launch')
    $file=Get-MsiId F ([guid]$Configuration.product.upgradeCode) ($Architecture+'/'+$Configuration.application.executable.Replace('\','/'))
    Event $dialog Finish MsiLaunchApp ('"[#'+$file+']"') ('UILevel = 5 AND WBTLAUNCHAPP = 1 AND NOT Installed AND NOT REMOVE AND NOT REINSTALL AND NOT MsiSystemRebootPending AND NOT ReplacedInUseFiles') 2
   }
   $linkX=$x
   foreach($link in @(@('ReleaseNotesLink','releaseNotesUrl','Release notes'),@('HelpLink','helpUrl','Getting started'))) {
    if(!$completion[$link[1]]){continue}
    $url=ConvertTo-MsiFormattedLiteral ([Net.WebUtility]::HtmlEncode($completion[$link[1]]))
    Control $dialog $link[0] Hyperlink $linkX 192 115 18 3 $null ('<a href="'+$url+'">'+$link[2]+'</a>')
    Visibility $dialog $link[0] $offer;$cycle.Add($link[0]);$linkX+=125
   }
  }
  if($details) {
   Control $dialog Details PushButton $x 215 132 21 3 $null 'Installation &details...'
   Event $dialog Details SpawnDialog WbtInstallDetails;$cycle.Add('Details')
  }
  Cycle $dialog $cycle.ToArray()
 }
 if($sidebar) {
  Sidebar WbtWelcome
  foreach($row in @($Model.Control.Rows | Where-Object {$_[0] -ceq 'WbtWelcome' -and $_[1] -in @('Heading','Subtitle','Message')})) {
   $row[3]=140;$row[5]=240
   switch($row[1]){Heading {$row[4]=25;$row[6]=55} Subtitle {$row[4]=87;$row[6]=48} Message {$row[4]=144;$row[6]=65}}
  }
 }
 # Header logo on intermediate pages and compact welcome/result pages. Scope
 # owns its own bounded table model and applies the matching helper separately.
 $logo=@(Get-MsiBrandingSpecs $Configuration | Where-Object Name -CEQ WbtUiLogo)
 if($logo.Count) {
  foreach($dialog in @($Model.Dialog.Rows | ForEach-Object {$_[0]})) {
   if($sidebar -and $dialog -in @('WbtWelcome','WbtExit','WbtUserExit','WbtFatalError')) {continue}
   foreach($row in @($Model.Control.Rows | Where-Object {$_[0] -ceq $dialog -and ($_[1] -like 'Heading*' -or $_[1] -ceq 'Subtitle')})) {$row[5]=300}
   Control $dialog HeaderLogo $logo[0].Kind 340 16 40 40 1 $null WbtUiLogo
  }
 }
}
