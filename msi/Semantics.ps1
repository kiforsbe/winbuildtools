#requires -Version 7.4
<#
.SYNOPSIS
Compare the complete supported MSI data surface before running native costing.
.DESCRIPTION
Expected rows come from the consumer configuration and approved payload, not from
the MSI being inspected. Null database cells compare as empty strings, as returned
by Windows Installer Automation. Row order is irrelevant; duplicates are not.
No database writes, installation sessions or extraction occur in this module.
#>
function Get-MsiSemanticColumns {
 @{
  Property=@('Property','Value')
  Icon=@('Name')
  Directory=@('Directory','Directory_Parent','DefaultDir')
  Component=@('Component','ComponentId','Directory_','Attributes','Condition','KeyPath')
  File=@('File','Component_','FileName','FileSize','Version','Language','Attributes','Sequence')
  MsiFileHash=@('File_','Options','HashPart1','HashPart2','HashPart3','HashPart4')
  Feature=@('Feature','Feature_Parent','Title','Description','Display','Level','Directory_','Attributes')
  FeatureComponents=@('Feature_','Component_')
  Media=@('DiskId','LastSequence','DiskPrompt','Cabinet','VolumeLabel','Source')
  Upgrade=@('UpgradeCode','VersionMin','VersionMax','Language','Attributes','Remove','ActionProperty')
  LaunchCondition=@('Condition','Description')
  Signature=@('Signature','FileName','MinVersion','MaxVersion','MinSize','MaxSize','MinDate','MaxDate','Languages')
  AppSearch=@('Property','Signature_')
  RegLocator=@('Signature_','Root','Key','Name','Type')
  Shortcut=@('Shortcut','Directory_','Name','Component_','Target','Arguments','Description','Hotkey','Icon_','IconIndex','ShowCmd','WkDir')
  CreateFolder=@('Directory_','Component_')
  RemoveFile=@('FileKey','Component_','FileName','DirProperty','InstallMode')
  InstallExecuteSequence=@('Action','Condition','Sequence')
  InstallUISequence=@('Action','Condition','Sequence')
 }
}
function Assert-MsiRowsMatch([string]$Table,[object[]]$Actual,[string[]]$Columns,[object[]]$Expected) {
 # Serialize column arrays, not delimiter-joined values: localized data can
 # legitimately contain punctuation. Always retain duplicate rows in comparison.
 $actualKeys=@(foreach($row in $Actual) {
  $values=@(foreach($column in $Columns) { [string]$row.$column })
  ConvertTo-Json -InputObject $values -Compress
 }) | Sort-Object -CaseSensitive
 $expectedKeys=@(foreach($row in $Expected) {
  $values=@(foreach($value in $row) { [string]$value })
  ConvertTo-Json -InputObject $values -Compress
 }) | Sort-Object -CaseSensitive
 if(@($actualKeys).Count -ne @($expectedKeys).Count -or ($actualKeys -join "`n") -cne ($expectedKeys -join "`n")) { throw "MSI semantic table mismatch: $Table." }
}
function Assert-MsiSemantics($Snapshot,$Configuration,[object[]]$Files,[string]$Version,[string]$Architecture) {
 $columns=Get-MsiSemanticColumns
 $rows=@{}; foreach($name in $columns.Keys) { $rows[$name]=[Collections.Generic.List[object]]::new() }
 $product=$Configuration.product; $installation=$Configuration.installation
 $properties=@{
  ProductName=$product.name;ProductVersion=$Version;ProductLanguage='1033';Manufacturer=$product.manufacturer
  ProductCode=(Get-MsiPackageGuid $Configuration $Architecture "product/$Version");UpgradeCode=(Get-MsiPackageGuid $Configuration $Architecture upgrade)
  INSTALLLEVEL='1';ARPNOMODIFY='1';REBOOT='ReallySuppress';MSIRESTARTMANAGERCONTROL='0';MSIRMSHUTDOWN='0';MSIDISABLERMRESTART='1'
  SecureCustomProperties='OLDERVERSIONS;NEWERVERSIONS;APPWINDOWSBUILD';DefaultUIFont='WbtUIFont';ErrorDialog='WbtError'
 }
 foreach($entry in (Get-MsiScopeProperties $Configuration).GetEnumerator()) { $properties[$entry.Key]=$entry.Value }
 $wordCount=2
 $installName=$installation.directoryName+' ('+$Architecture.ToLowerInvariant()+')'; $menuName=$installName
 if($Configuration.schemaVersion -eq 2) {
  $installName=$installation.directoryName; $menuName=$installation.menuDirectoryName
  if($installation.scope -ne 'machine') { $wordCount=10 }
  if($installation.restartManager -eq 'disabled') { $properties.MSIRESTARTMANAGERCONTROL='Disable' }
  $properties.SecureCustomProperties+=';ALLUSERS;MSIINSTALLPERUSER;WBTINSTALLSCOPE'
 }
 $iconName=if($Configuration.application.icon) {'App.exe'}else{$null}
 if($iconName) { $properties.ARPPRODUCTICON=$iconName; $rows.Icon.Add(@($iconName)) }
 foreach($entry in $properties.GetEnumerator()) { $rows.Property.Add(@($entry.Key,$entry.Value)) }
 if($Snapshot.Codepage -ne 1252 -or $Snapshot.Title -cne ($product.name+' installer') -or $Snapshot.Subject -cne $product.name -or $Snapshot.Author -cne $product.manufacturer -or $Snapshot.PageCount -ne 500 -or $Snapshot.WordCount -ne $wordCount -or $Snapshot.CreatingApplication -cne 'Generic MSI packaging' -or $Snapshot.Template -cne $(if($Architecture -eq 'ARM64'){'Arm64;1033'}else{'x64;1033'})) { throw 'MSI summary metadata/privilege mismatch.' }
 $packageGuid=[guid]::Empty
 if(![guid]::TryParseExact([string]$Snapshot.PackageCode,'B',[ref]$packageGuid) -or $packageGuid -eq [guid]::Empty -or $Snapshot.PackageCode -in @($properties.ProductCode,$properties.UpgradeCode)+@($Configuration.components.Values)) { throw 'MSI package identity must be a fresh nonzero GUID.' }
 $installShort='A'+(Get-MsiPackageId $Configuration $Architecture D install-root).Substring(1,7)
 $menuShort='M'+(Get-MsiPackageId $Configuration $Architecture D menu-root).Substring(1,7)
 foreach($row in @(@('TARGETDIR',$null,'SourceDir'),@('ProgramFiles64Folder','TARGETDIR','PFiles64'),@('INSTALLFOLDER','ProgramFiles64Folder',($installShort+'|'+$installName)),@('ProgramMenuFolder','TARGETDIR','PMenu'),@('APPMENUDIR','ProgramMenuFolder',($menuShort+'|'+$menuName)))) { $rows.Directory.Add($row) }
 $directories=@{''='INSTALLFOLDER'}
 $main=@($Files | Where-Object Relative -EQ $Configuration.application.executable.Replace('\','/'))[0]
 $engine=$null
 try {
  # Obtain native fixed versions and four-part hashes from approved input bytes.
  # This Automation object never opens an installation session.
  $engine=New-Object -ComObject WindowsInstaller.Installer
  foreach($file in $Files) {
   $parent='INSTALLFOLDER'; $scope=''
   foreach($segment in @([IO.Path]::GetDirectoryName($file.Relative).Replace('\','/').Split('/') | Where-Object {$_})) {
    $scope=if($scope){$scope+'/'+$segment}else{$segment}
    if(!$directories.ContainsKey($scope)) {
     $id=Get-MsiPackageId $Configuration $Architecture D $scope
     $rows.Directory.Add(@($id,$parent,('D'+$id.Substring(1,7)+'|'+$segment))); $directories[$scope]=$id
    }
    $parent=$directories[$scope]
   }
   $rows.Component.Add(@($file.Component,(Get-MsiPackageGuid $Configuration $Architecture ('component/'+$file.Relative)),$parent,256,$null,$file.Id))
   $rows.FeatureComponents.Add(@('Main',$file.Component))
   $versionValue=$engine.FileVersion($file.FullName,$false)
   $extension=[IO.Path]::GetExtension($file.Name); if($extension.Length -gt 4) { $extension='' }
   $short='F'+$file.Id.Substring(1,7)+$extension
   $rows.File.Add(@($file.Id,$file.Component,($short+'|'+$file.Name),$file.Length,$versionValue,$null,512,([array]::IndexOf($Files,$file)+1)))
   if(!$versionValue) {
    $hash=$engine.FileHash($file.FullName,0)
    try { $rows.MsiFileHash.Add(@($file.Id,0,$hash.IntegerData(1),$hash.IntegerData(2),$hash.IntegerData(3),$hash.IntegerData(4))) } finally { Close-MsiCom $hash }
   }
  }
 } finally { Close-MsiCom $engine }
 $rows.Feature.Add(@('Main',$null,$product.name,$product.name,1,1,'INSTALLFOLDER',0))
 $rows.Media.Add(@(1,$Files.Count,$null,'#payload.cab',$null,$null))
 $rows.Upgrade.Add(@($properties.UpgradeCode,$null,$Version,$null,0,$null,'OLDERVERSIONS'))
 $rows.Upgrade.Add(@($properties.UpgradeCode,$Version,$null,$null,258,$null,'NEWERVERSIONS'))
 $rows.RegLocator.Add(@('WindowsBuild',2,'SOFTWARE\Microsoft\Windows NT\CurrentVersion','CurrentBuildNumber',18))
 $rows.AppSearch.Add(@('APPWINDOWSBUILD','WindowsBuild'))
 $rows.LaunchCondition.Add(@(('Installed OR (VersionNT64 AND APPWINDOWSBUILD >= '+$installation.minimumWindowsBuild+')'),('Requires Windows build '+$installation.minimumWindowsBuild+' or later ('+$Architecture+').')))
 $rows.LaunchCondition.Add(@('Installed OR NOT NEWERVERSIONS','The same or a newer version is already installed.'))
 $index=0
 foreach($shortcut in $Configuration.shortcuts) {
  $short='S'+(Get-MsiPackageId $Configuration $Architecture S ('shortcut/'+$shortcut.name)).Substring(1,7)
  $rows.Shortcut.Add(@(('Shortcut'+(++$index)),'APPMENUDIR',($short+'|'+$shortcut.name),$main.Component,'Main',$null,$product.name,$null,$iconName,$null,1,'INSTALLFOLDER'))
 }
 foreach($id in @($directories.Values)+@('APPMENUDIR')) { $rows.CreateFolder.Add(@($id,$main.Component)) }
 $rows.RemoveFile.Add(@('RemoveStartMenuFolder',$main.Component,$null,'APPMENUDIR',2))
 $actions=@{FindRelatedProducts=25;AppSearch=50;LaunchConditions=100;ValidateProductID=700;CostInitialize=800;FileCost=900;CostFinalize=1000;MigrateFeatureStates=1200;InstallValidate=1400;InstallInitialize=1500;RemoveExistingProducts=1510;ProcessComponents=1600;UnpublishFeatures=1800;RemoveShortcuts=3200;RemoveFiles=3500;RemoveFolders=3600;CreateFolders=3700;InstallFiles=4000;CreateShortcuts=4500;RegisterUser=6000;RegisterProduct=6100;PublishFeatures=6300;PublishProduct=6400;InstallFinalize=6600}
 foreach($entry in $actions.GetEnumerator()) { $rows.InstallExecuteSequence.Add(@($entry.Key,$null,$entry.Value)) }
 foreach($name in @('FindRelatedProducts','AppSearch','LaunchConditions','CostInitialize','FileCost','CostFinalize','MigrateFeatureStates')) { $rows.InstallUISequence.Add(@($name,$null,$actions[$name])) }
 $rows.InstallUISequence.Add(@('ExecuteAction',$null,1300))
 foreach($entry in @{WbtExit=-1;WbtUserExit=-2;WbtFatalError=-3}.GetEnumerator()) { $rows.InstallUISequence.Add(@($entry.Key,'UILevel = 5',$entry.Value)) }
 if($Configuration.schemaVersion -eq 2 -and $installation.scope -eq 'choice') { $rows.InstallUISequence.Add(@('WbtScope','NOT Installed AND UILevel = 5',10)) }
 foreach($name in $columns.Keys) { Assert-MsiRowsMatch $name @($Snapshot.SemanticTables[$name]) $columns[$name] $rows[$name].ToArray() }
 # Restrict table presence, including empty forbidden tables, not just row counts.
 $allowed=@($columns.Keys)+@('Dialog','Control','ControlEvent','ListBox','TextStyle','AdminUISequence')
 if($Configuration.schemaVersion -eq 2 -and $installation.scope -eq 'choice') { $allowed+='RadioButton' }
 if(@($Snapshot.Tables | Where-Object { $_ -notin $allowed }).Count) { throw 'MSI contains unsupported authoring tables.' }
}
