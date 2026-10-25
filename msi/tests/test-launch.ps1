#requires -Version 7.4
<#
.SYNOPSIS
Exercise the authored Finish launch event with an isolated marker executable.
.DESCRIPTION
Run explicitly on a Windows desktop. A bounded STA subprocess costs synthetic
packages and opens only WbtExit; both sequence tables are emptied before opening
the packages. No product is installed, registered, repaired or removed. The only
executable allowed to run is an owned compiled fixture that writes a temp marker.
The subprocess clicks Finish only in its own uniquely titled window. Requires
the Windows .NET Framework C# compiler; never downloads a compiler or package.
.PARAMETER Worker
Internal bounded subprocess entry point; normally omit this switch.
#>
[CmdletBinding()]
param([switch]$Worker)
$ErrorActionPreference='Stop'
if(!$IsWindows){throw 'Native launch verification requires Windows.'}
if(!$Worker) {
 $start=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle='Hidden'
 $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 foreach($argument in @('-NoProfile','-STA','-File',$PSCommandPath,'-Worker')){$start.ArgumentList.Add($argument)}
 $process=[Diagnostics.Process]::new();$process.StartInfo=$start
 try {
  if(!$process.Start()){throw 'Cannot start the native launch fixture.'}
  $output=$process.StandardOutput.ReadToEndAsync();$errors=$process.StandardError.ReadToEndAsync()
  if(!$process.WaitForExit(60000)){$process.Kill($true);$process.WaitForExit();throw 'Native launch fixture exceeded 60 seconds; only its owned subprocess was terminated.'}
  $stdout=$output.GetAwaiter().GetResult();$stderr=$errors.GetAwaiter().GetResult()
  if($process.ExitCode -ne 0){throw "Native launch fixture failed: $stdout $stderr"}
  Write-Host $stdout.Trim()
 }finally{$process.Dispose()}
 return
}
if([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'){throw 'The native launch worker requires STA.'}
$engine=Split-Path $PSScriptRoot -Parent
foreach($name in @('Configuration','Identity','Branding','Payload','Database','Registration','Maintenance','Scope','Presentation','Wizard','Semantics','Authoring','Inspection')){. "$engine/$name.ps1"}
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture=Join-Path $tempRoot ('WbtLaunch-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory "$fixture/payload with spaces"
$marker=Join-Path $fixture marker.txt
try {
 $compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
 if(!(Test-Path -LiteralPath $compiler)){throw 'Native launch fixture requires the Windows .NET Framework C# compiler.'}
 $code='using System.IO; class Marker { static void Main() { File.WriteAllText(@"'+$marker.Replace('"','""')+'", "launched"); } }'
 [IO.File]::WriteAllText((Join-Path $fixture marker.cs),$code)
 $executable=[IO.Path]::GetFullPath("$fixture/payload with spaces/Marker.exe")
 # The inbox compiler needs Windows-normalized paths, including its /out value.
 & $compiler /nologo /target:winexe ('/out:'+$executable) (Join-Path $fixture marker.cs)
 if($LASTEXITCODE -ne 0){throw 'Cannot compile the marker fixture.'}
 Add-Type -TypeDefinition @'
using System;using System.Diagnostics;using System.Runtime.InteropServices;using System.Text;using System.Threading;
[assembly:DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
namespace WbtLaunchFixture {
 public static class ClickOwnFinish {
  delegate bool Callback(IntPtr h,IntPtr p);
  [DllImport("user32.dll")]static extern bool EnumWindows(Callback c,IntPtr p);
  [DllImport("user32.dll")]static extern bool EnumChildWindows(IntPtr h,Callback c,IntPtr p);
  [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint id);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern IntPtr SendMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
  static Timer timer;static int clicked;
  static string Text(IntPtr h){var b=new StringBuilder(512);GetWindowText(h,b,512);return b.ToString();}
  public static bool Clicked {get{return Volatile.Read(ref clicked)!=0;}}
  public static void Start(string title,bool clearLaunch){clicked=0;timer=new Timer(_=>{
   EnumWindows((h,p)=>{uint id;GetWindowThreadProcessId(h,out id);if(id!=(uint)Process.GetCurrentProcess().Id||Text(h)!=title)return true;
    if(Interlocked.CompareExchange(ref clicked,1,0)!=0)return false;
    // Exercise the real checkbox click before Finish, rather than resetting its
    // property in the test. Only this worker's uniquely titled dialog is touched.
    if(clearLaunch)EnumChildWindows(h,(child,q)=>{if(!Text(child).StartsWith("Launch "))return true;
     SendMessage(child,245,IntPtr.Zero,IntPtr.Zero);return false;},IntPtr.Zero);
    EnumChildWindows(h,(child,q)=>{if(Text(child).Replace("&","")!="Finish")return true;
     SendMessage(child,245,IntPtr.Zero,IntPtr.Zero);return false;},IntPtr.Zero);return false;},IntPtr.Zero);
  },null,200,200);}
  public static void Stop(){var t=timer;timer=null;if(t!=null)t.Dispose();}
 }
}
'@
 $cfg=Read-MsiConfiguration "$engine/example.json"
 $cfg.product.name='Wbt launch fixture '+[guid]::NewGuid().ToString('N')
 $cfg.product.upgradeCode=[guid]::NewGuid().ToString('B')
 $cfg.application=@{executable='Marker.exe'}
 $cfg.payload=@{requiredFiles=@('Marker.exe');allowedExtensions=@('.exe');allowedFiles=@()}
 $cfg.ui=@{completion=@{launchApplication=$true;showDetails=$false}}
 $architecture=if([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64'){'ARM64'}else{'x64'}
 New-MsiPackage $cfg "$fixture/payload with spaces" "$fixture/source.msi" '1.2.3' $architecture
 $cfg.ui.completion.launchApplicationChecked=$true
 New-MsiPackage $cfg "$fixture/payload with spaces" "$fixture/checked-source.msi" '1.2.3' $architecture
 # null leaves the authored property intact; empty string explicitly clears it.
 # The final flag exercises an actual native checkbox click before Finish.
 foreach($case in @(@('selected','1','','',$true,'source',$false),@('default-unchecked',$null,'','',$false,'source',$false),@('preselected',$null,'','',$true,'checked-source',$false),@('user-unchecked',$null,'','',$false,'checked-source',$true),@('machine-pending',$null,'1','',$true,'checked-source',$false),@('unchecked','','','',$false,'checked-source',$false),@('transaction-restart',$null,'','1',$false,'checked-source',$false))) {
  $path=Join-Path $fixture ($case[0]+'.msi');New-MsiPreflightCopy "$fixture/$($case[5]).msi" $path
  $installer=$null;$db=$null;$session=$null
  try {
   $installer=New-Object -ComObject WindowsInstaller.Installer;$installer.UILevel=5
   $db=$installer.OpenDatabase($path,1)
   # Remove every sequence entry before OpenPackage. Only explicit costing and
   # this final dialog are allowed below; no install transaction can be reached.
   foreach($table in @('InstallExecuteSequence','InstallUISequence')){Invoke-MsiSql $db ('DELETE FROM `'+$table+'`')}
   $null=$db.Commit();Close-MsiCom $db;$db=$null
   $session=$installer.OpenPackage([IO.Path]::GetFullPath($path),0)
   $session.Property('ALLUSERS')='2';$session.Property('MSIINSTALLPERUSER')='1'
   $session.Property('INSTALLFOLDER')=[IO.Path]::GetFullPath("$fixture/payload with spaces")+'\'
   $session.Property('APPMENUDIR')=[IO.Path]::GetFullPath("$fixture/menu")+'\'
   foreach($action in @('CostInitialize','FileCost','CostFinalize')){if($session.DoAction($action) -ne 1){throw "Fixture costing failed: $action"}}
   $expectedInitial=if($case[5] -eq 'checked-source'){'1'}else{''}
   if($session.Property('WBTLAUNCHAPP') -cne $expectedInitial){throw 'Incorrect authored Launch checkbox value.'}
   if($null -ne $case[1]){$session.Property('WBTLAUNCHAPP')=$case[1]}
   $session.Property('MsiSystemRebootPending')=$case[2];$session.Property('ReplacedInUseFiles')=$case[3]
   if(Test-Path -LiteralPath $marker){Remove-Item -LiteralPath $marker}
   [WbtLaunchFixture.ClickOwnFinish]::Start($cfg.product.name+' Setup',[bool]$case[6])
   try {$result=$session.DoAction('WbtExit')}finally{[WbtLaunchFixture.ClickOwnFinish]::Stop()}
   $watch=[Diagnostics.Stopwatch]::StartNew()
   while(!(Test-Path -LiteralPath $marker) -and $watch.Elapsed.TotalSeconds -lt 2){Start-Sleep -Milliseconds 50}
   if($result -ne 1 -or ![WbtLaunchFixture.ClickOwnFinish]::Clicked){throw "Fixture Finish was not completed: $($case[0])"}
   $launched=Test-Path -LiteralPath $marker
   if($launched -ne $case[4]){throw "Native Finish launch mismatch: $($case[0]); expected $($case[4]), observed $launched"}
   if($launched -and [IO.File]::ReadAllText($marker) -cne 'launched'){throw 'Invalid marker content.'}
   Write-Host "Native Finish launch passed: $($case[0])"
  }finally{Close-MsiCom $session;Close-MsiCom $db;Close-MsiCom $installer}
 }
}finally{
 $target=[IO.Path]::GetFullPath($fixture)
 if([IO.Path]::GetDirectoryName($target) -cne $tempRoot.TrimEnd('\') -or [IO.Path]::GetFileName($target) -notlike 'WbtLaunch-*'){throw 'Unsafe launch-fixture cleanup.'}
 Remove-Item -LiteralPath $target -Recurse -Force
}
