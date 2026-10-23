#requires -Version 7.4
<#
.SYNOPSIS
Display/capture native MSI dialogs without installing or executing actions.
.DESCRIPTION
Uses Windows Installer's inactive, modeless EnableUIPreview/ViewDialog interface.
Controls are intentionally inactive: this proves native rendering, not navigation,
focus, UAC or installed lifecycle. Opens the MSI database read-only, never creates
an installation session and never starts msiexec. Run PowerShell with -STA.
.PARAMETER Artifact
Existing MSI to preview. Original bytes are never changed.
.PARAMETER Dialog
Existing dialog names, displayed one at a time.
.PARAMETER SecondsPerDialog
Preview dwell time per dialog; message pumping keeps the native surface painted.
.PARAMETER CaptureDirectory
Optional new directory for PNG captures of only this process's preview window.
.EXAMPLE
pwsh -STA -Command { & ./msi/preview.ps1 -Artifact C:/build/app.msi -Dialog @('WbtWelcome','WbtReady') -CaptureDirectory C:/build/native-preview }
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Artifact,[string[]]$Dialog=@('WbtWelcome'),[ValidateRange(1,60)][int]$SecondsPerDialog=3,[string]$CaptureDirectory,[hashtable]$Properties=@{})
$ErrorActionPreference='Stop'
if(!$IsWindows -or [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Native preview requires Windows and pwsh -STA.' }
. "$PSScriptRoot/Configuration.ps1"
. "$PSScriptRoot/Database.ps1"
$path=Resolve-MsiPath $Artifact
if(!(Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Preview MSI not found.' }
if($CaptureDirectory) {
 $CaptureDirectory=Resolve-MsiPath $CaptureDirectory
 if(Test-Path -LiteralPath $CaptureDirectory) { throw 'CaptureDirectory must be new.' }
 $null=New-Item -ItemType Directory -Path $CaptureDirectory
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if(!('Wbt.NativePreview.Window' -as [type])) {
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[assembly:DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
namespace Wbt.NativePreview {
 public static class Window {
  delegate bool Callback(IntPtr window,IntPtr data);
  [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left,Top,Right,Bottom; }
  [DllImport("user32.dll")] static extern bool EnumWindows(Callback callback,IntPtr data);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out Rect rect);
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr window,IntPtr dc,uint flags);
  public static IntPtr Find(uint process) {
   IntPtr target=IntPtr.Zero;
   EnumWindows((window,data)=>{uint owner;GetWindowThreadProcessId(window,out owner);if(owner==process&&IsWindowVisible(window)) {target=window;return false;}return true;},IntPtr.Zero);
   if(target==IntPtr.Zero) throw new InvalidOperationException("No native preview window found.");
   return target;
  }
  public static int[] Bounds(IntPtr target) {
   Rect rect;if(!GetWindowRect(target,out rect)) throw new InvalidOperationException("Cannot read preview bounds.");
   return new int[]{rect.Right-rect.Left,rect.Bottom-rect.Top};
  }
  public static bool Print(IntPtr target,IntPtr dc) { return PrintWindow(target,dc,2); }
 }
}
'@
}
$installer=$null;$database=$null;$preview=$null
try {
 $installer=New-Object -ComObject WindowsInstaller.Installer;$database=$installer.OpenDatabase($path,0)
 $names=@(Get-MsiRows $database Dialog @('Dialog') | ForEach-Object Dialog)
 foreach($name in $Dialog) { if($name -notin $names -or $name -notmatch '^[A-Za-z][A-Za-z0-9_]*$') { throw "Unknown/unsafe preview dialog: $name" } }
 $preview=$database.EnableUIPreview()
 foreach($row in Get-MsiRows $database Property @('Property','Value')) { $preview.Property($row.Property)=$row.Value }
 foreach($entry in $Properties.GetEnumerator()) {
  if($entry.Key -notmatch '^[A-Za-z][A-Za-z0-9_]*$' -or $entry.Value -isnot [string]) { throw 'Preview properties must be named strings.' }
  $preview.Property($entry.Key)=$entry.Value
 }
 foreach($name in $Dialog) {
  try { $null=$preview.ViewDialog($name) }
  catch {
   $record=$installer.LastErrorRecord
   try { $detail=if($record) {$record.FormatText()}else{[string]$_} } finally { Close-MsiCom $record }
   throw "Native preview failed for ${name}: $detail"
  }
  $watch=[Diagnostics.Stopwatch]::StartNew()
  while($watch.Elapsed.TotalSeconds -lt $SecondsPerDialog) { [Windows.Forms.Application]::DoEvents();[Threading.Thread]::Sleep(20) }
  if($CaptureDirectory) {
   $window=[Wbt.NativePreview.Window]::Find([uint32]$PID);$bounds=[Wbt.NativePreview.Window]::Bounds($window)
   $bitmap=[Drawing.Bitmap]::new($bounds[0],$bounds[1]);$graphics=$null
   try {
    $graphics=[Drawing.Graphics]::FromImage($bitmap);$dc=$graphics.GetHdc()
    try { if(![Wbt.NativePreview.Window]::Print($window,$dc)) { throw 'Cannot capture preview window.' } } finally { $graphics.ReleaseHdc($dc) }
    $bitmap.Save((Join-Path $CaptureDirectory ($name+'.png')),[Drawing.Imaging.ImageFormat]::Png)
   } finally { if($graphics) {$graphics.Dispose()};$bitmap.Dispose() }
  }
  Write-Host "Native inactive preview: $name"
 }
} finally { if($preview) { $null=$preview.ViewDialog('') };Close-MsiCom $preview;Close-MsiCom $database;Close-MsiCom $installer }
