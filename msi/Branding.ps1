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
function Assert-MsiBrandingAssets($Configuration,[string]$Folder) {
 foreach($spec in @(Get-MsiBrandingSpecs $Configuration)) {
  $path=Join-Path $Folder $spec.Relative
  if((Get-Item -LiteralPath $path).Length -gt 8MB) { throw 'Wizard image exceeds 8 MiB.' }
  Add-Type -AssemblyName System.Drawing
  $stream=$null;$image=$null
  try {
   $stream=[IO.File]::OpenRead($path)
   $image=if($spec.Kind -eq 'Icon'){[Drawing.Icon]::new($stream)}else{[Drawing.Image]::FromStream($stream,$false,$true)}
   if($image.Width -lt 1 -or $image.Height -lt 1 -or $image.Width -gt 2048 -or $image.Height -gt 2048) { throw 'Wizard image dimensions must be 1..2048 pixels.' }
   if($spec.Kind -eq 'Bitmap') {
    $expected=switch([IO.Path]::GetExtension($path).ToLowerInvariant()){'.png' {[Drawing.Imaging.ImageFormat]::Png.Guid} '.bmp' {[Drawing.Imaging.ImageFormat]::Bmp.Guid} default {[Drawing.Imaging.ImageFormat]::Jpeg.Guid}}
    if($image.RawFormat.Guid -ne $expected) { throw 'Wizard image content does not match its extension.' }
   }
  } finally {if($image){$image.Dispose()};if($stream){$stream.Dispose()}}
 }
}
function Add-MsiBranding($Installer,$Database,$Configuration,[string]$Folder) {
 foreach($spec in @(Get-MsiBrandingSpecs $Configuration)) { Add-MsiRow $Installer $Database Binary @('Name','Data') @($spec.Name,(Join-Path $Folder $spec.Relative)) @(1) }
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
 foreach($spec in $specs) { if((Get-MsiBrandingHash $Path $spec.Name) -cne (Get-FileHash -LiteralPath (Join-Path $Folder $spec.Relative) -Algorithm SHA256).Hash) { throw 'MSI wizard image bytes differ from the approved payload.' } }
}
