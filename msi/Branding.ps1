#requires -Version 7.4
<#
.SYNOPSIS
Bounded consumer image resources for native MSI dialogs.
.DESCRIPTION
Loaded before Payload; database helpers are required when authoring/inspecting.
Only explicit approved payload assets are used. Decode/size checks run before
output creation. Binary resource names and bytes are compared before preflight.
No graphics package, downloaded content, executable stream or install action.
#>
function Get-MsiBrandingSpecs($Configuration) {
 foreach($field in @('logo','sidebarImage')) {
  $relative=$Configuration.ui.$field
  if($relative) {
   [pscustomobject]@{Name=$(if($field -eq 'logo'){'WbtUiLogo'}else{'WbtUiSidebar'});Relative=$relative.Replace('\','/');Kind=$(if([IO.Path]::GetExtension($relative) -ieq '.ico'){'Icon'}else{'Bitmap'})}
  }
 }
}
function Get-MsiBrandingBytes([string]$Path) {
 # MSI's native Icon control loads the first ICO frame when no IconSize bits
 # are set. Put the best available frame first; keep all encoded image data,
 # offsets and remaining entry order intact. The installed payload is untouched.
 if((Get-Item -LiteralPath $Path).Length -gt 8MB) {throw 'Wizard image exceeds 8 MiB.'}
 $bytes=[IO.File]::ReadAllBytes($Path)
 if([IO.Path]::GetExtension($Path) -ine '.ico') {return ,$bytes}
 if($bytes.Length -lt 6 -or [BitConverter]::ToUInt16($bytes,0) -ne 0 -or [BitConverter]::ToUInt16($bytes,2) -ne 1) {throw 'Invalid wizard ICO header.'}
 $count=[BitConverter]::ToUInt16($bytes,4);$directoryEnd=6+16*$count
 if(!$count -or $directoryEnd -gt $bytes.Length) {throw 'Invalid wizard ICO directory.'}
 $best=0;$bestArea=0;$bestDepth=0
 for($i=0;$i -lt $count;$i++) {
  $entry=6+16*$i
  $length=[BitConverter]::ToUInt32($bytes,$entry+8);$offset=[BitConverter]::ToUInt32($bytes,$entry+12)
  if($bytes[$entry+3] -ne 0 -or !$length -or $offset -lt $directoryEnd -or ([uint64]$offset+$length) -gt $bytes.Length) {throw 'Invalid wizard ICO frame range.'}
  $width=if($bytes[$entry]){[int]$bytes[$entry]}else{256}
  $height=if($bytes[$entry+1]){[int]$bytes[$entry+1]}else{256}
  $area=$width*$height;$depth=[BitConverter]::ToUInt16($bytes,$entry+6)
  # Keep original order for equal size/depth; deterministic normalization makes
  # independent inspection reproduce the exact embedded resource hash.
  if($area -gt $bestArea -or ($area -eq $bestArea -and $depth -gt $bestDepth)) {$best=$i;$bestArea=$area;$bestDepth=$depth}
 }
 if($best -gt 0) {
  $entries=[byte[]]::new(16*$count);[Array]::Copy($bytes,6,$entries,0,$entries.Length)
  [Array]::Copy($entries,16*$best,$bytes,6,16)
  [Array]::Copy($entries,0,$bytes,22,16*$best)
 }
 return ,$bytes
}
function Assert-MsiBrandingAssets($Configuration,[string]$Folder) {
 foreach($spec in @(Get-MsiBrandingSpecs $Configuration)) {
  $path=Join-Path $Folder $spec.Relative
  if((Get-Item -LiteralPath $path).Length -gt 8MB) { throw 'Wizard image exceeds 8 MiB.' }
  Add-Type -AssemblyName System.Drawing
  $stream=$null;$image=$null;$bitmap=$null
  try {
   if($spec.Kind -eq 'Icon') {
    # Isolate the selected frame in a one-entry ICO so the native decoder cannot
    # fall back to a valid small frame when the chosen high-resolution one is bad.
    $bytes=Get-MsiBrandingBytes $path
    $length=[BitConverter]::ToUInt32($bytes,14);$offset=[BitConverter]::ToUInt32($bytes,18)
    $selected=[byte[]]::new(22+$length)
    [Array]::Copy($bytes,0,$selected,0,22);$selected[4]=1;$selected[5]=0
    [BitConverter]::GetBytes([uint32]22).CopyTo($selected,18)
    [Array]::Copy($bytes,$offset,$selected,22,$length)
    $stream=[IO.MemoryStream]::new($selected,$false);$image=[Drawing.Icon]::new($stream)
    $bitmap=$image.ToBitmap()
    $width=if($bytes[6]){[int]$bytes[6]}else{256};$height=if($bytes[7]){[int]$bytes[7]}else{256}
    if($bitmap.Width -ne $width -or $bitmap.Height -ne $height) {throw 'Wizard ICO frame dimensions differ from its directory.'}
   } else {
    $stream=[IO.File]::OpenRead($path);$image=[Drawing.Image]::FromStream($stream,$false,$true)
   }
   if($image.Width -lt 1 -or $image.Height -lt 1 -or $image.Width -gt 2048 -or $image.Height -gt 2048) { throw 'Wizard image dimensions must be 1..2048 pixels.' }
   if($spec.Kind -eq 'Bitmap') {
    $expected=switch([IO.Path]::GetExtension($path).ToLowerInvariant()){'.png' {[Drawing.Imaging.ImageFormat]::Png.Guid} '.bmp' {[Drawing.Imaging.ImageFormat]::Bmp.Guid} default {[Drawing.Imaging.ImageFormat]::Jpeg.Guid}}
    if($image.RawFormat.Guid -ne $expected) { throw 'Wizard image content does not match its extension.' }
   }
  } finally {if($bitmap){$bitmap.Dispose()};if($image){$image.Dispose()};if($stream){$stream.Dispose()}}
 }
}
function Add-MsiBranding($Installer,$Database,$Configuration,[string]$Folder) {
 foreach($spec in @(Get-MsiBrandingSpecs $Configuration)) {
  $source=Join-Path $Folder $spec.Relative
  if($spec.Kind -ne 'Icon') {Add-MsiRow $Installer $Database Binary @('Name','Data') @($spec.Name,$source) @(1);continue}
  # Own an atomically created, unpredictable temp file for the derived resource.
  # SetStream needs a closed file on Windows; remove only our created file in
  # finally, including when native stream authoring fails.
  $temporary=Join-Path ([IO.Path]::GetTempPath()) ('WbtBranding-'+[guid]::NewGuid().ToString('N')+'.ico')
  $stream=$null;$created=$false
  try {
   $stream=[IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$created=$true
   $bytes=Get-MsiBrandingBytes $source;$stream.Write($bytes,0,$bytes.Length);$stream.Flush()
   $stream.Dispose();$stream=$null
   Add-MsiRow $Installer $Database Binary @('Name','Data') @($spec.Name,$temporary) @(1)
  } finally {if($stream){$stream.Dispose()};if($created){Remove-Item -LiteralPath $temporary -Force}}
 }
}
function Get-MsiBrandingHash([string]$Path,[ValidateSet('WbtUiLogo','WbtUiSidebar')][string]$Name) {
 # Read a parameter-bound Binary stream through msi.dll. A modified package can
 # contain oversized streams; enforce the same byte bound without extracting it.
 if(!('Wbt.Branding.StreamHash' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
[assembly:DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
namespace Wbt.Branding {
 public static class StreamHash {
  [DllImport("msi.dll",CharSet=CharSet.Unicode)] static extern uint MsiOpenDatabase(string path,IntPtr mode,out uint db);
  [DllImport("msi.dll",CharSet=CharSet.Unicode)] static extern uint MsiDatabaseOpenView(uint db,string sql,out uint view);
  [DllImport("msi.dll")] static extern uint MsiCreateRecord(uint count);
  [DllImport("msi.dll",CharSet=CharSet.Unicode)] static extern uint MsiRecordSetString(uint record,uint field,string value);
  [DllImport("msi.dll")] static extern uint MsiViewExecute(uint view,uint parameters);
  [DllImport("msi.dll")] static extern uint MsiViewFetch(uint view,out uint record);
  [DllImport("msi.dll")] static extern uint MsiRecordReadStream(uint record,uint field,byte[] buffer,ref uint count);
  [DllImport("msi.dll")] static extern uint MsiCloseHandle(uint handle);
  static void Check(uint code){if(code!=0)throw new Win32Exception((int)code);}
  public static string Read(string path,string name) {
   uint db=0,view=0,parameters=0,record=0;
   try {
    Check(MsiOpenDatabase(path,IntPtr.Zero,out db));
    Check(MsiDatabaseOpenView(db,"SELECT `Data` FROM `Binary` WHERE `Name`=?",out view));
    parameters=MsiCreateRecord(1);if(parameters==0)throw new InvalidOperationException("Cannot create MSI parameters.");
    Check(MsiRecordSetString(parameters,1,name));Check(MsiViewExecute(view,parameters));Check(MsiViewFetch(view,out record));
    using(var bytes=new MemoryStream()) {
     var buffer=new byte[65536];
     while(true){uint count=(uint)buffer.Length;Check(MsiRecordReadStream(record,1,buffer,ref count));if(count==0)break;
      if(bytes.Length+count>8388608)throw new InvalidDataException("Wizard resource exceeds 8 MiB.");bytes.Write(buffer,0,(int)count);}
     bytes.Position=0;using(var sha=SHA256.Create())return Convert.ToHexString(sha.ComputeHash(bytes));
    }
   } finally {if(record!=0)MsiCloseHandle(record);if(parameters!=0)MsiCloseHandle(parameters);if(view!=0)MsiCloseHandle(view);if(db!=0)MsiCloseHandle(db);}
  }
 }
}
'@
 }
 [Wbt.Branding.StreamHash]::Read($Path,$Name)
}
function Assert-MsiBrandingPolicy([string]$Path,$Configuration,[string]$Folder) {
 $specs=@(Get-MsiBrandingSpecs $Configuration)
 $installer=$null;$database=$null
 try {
  $installer=New-Object -ComObject WindowsInstaller.Installer;$database=$installer.OpenDatabase($Path,0)
  Assert-MsiRowsMatch Binary @(Get-MsiRows $database Binary @('Name')) @('Name') @($specs | ForEach-Object {,@($_.Name)})
 } finally {Close-MsiCom $database;Close-MsiCom $installer}
 foreach($spec in $specs) {
  $expected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData((Get-MsiBrandingBytes (Join-Path $Folder $spec.Relative))))
  if((Get-MsiBrandingHash $Path $spec.Name) -cne $expected) {throw 'MSI wizard image bytes differ from the approved payload resource.'}
 }
}
