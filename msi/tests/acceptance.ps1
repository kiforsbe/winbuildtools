#requires -Version 7.4
<#
.SYNOPSIS
Prepare synthetic MSI acceptance fixtures; optionally run a disposable-host lifecycle.
.DESCRIPTION
Default mode only prepares two unsigned synthetic packages and a manifest. It
never installs. -RunLifecycle additionally requires -DisposableHost and performs
silent install, destructive-file repair, custom-folder upgrade and removal of
ONLY freshly generated test identities. Never point this at a daily workstation.
The fixture copies this host's PowerShell executable as inert PE bytes for native
icons/shortcut identity; it is never launched and must not be redistributed.
Artifacts/logs are retained. Real Start-menu UI, UAC, keyboard, rollback, DPI and
files-in-use acceptance remain explicit manual checks described in the guide.
.PARAMETER OutputDirectory
New directory for retained packages, configurations, manifest and logs.
.PARAMETER RunLifecycle
Actually install/repair/upgrade/remove the newly generated synthetic packages.
.PARAMETER DisposableHost
Explicit confirmation that this is an isolated disposable Windows installation.
.PARAMETER Scope
User (default) or machine. Machine lifecycle requires an elevated disposable host.
.EXAMPLE
./msi/tests/acceptance.ps1 -OutputDirectory C:/build/wbt-acceptance
.EXAMPLE
./msi/tests/acceptance.ps1 -OutputDirectory C:/build/wbt-lifecycle -RunLifecycle -DisposableHost -Scope user
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,[switch]$RunLifecycle,[switch]$DisposableHost,[ValidateSet('user','machine')][string]$Scope='user')
$ErrorActionPreference='Stop'
if($RunLifecycle -and !$DisposableHost) { throw 'Running lifecycle requires explicit -DisposableHost on an isolated disposable Windows installation.' }
if(!$IsWindows) { throw 'Windows is required.' }
$engine=Split-Path $PSScriptRoot -Parent
foreach($name in @('Configuration','Identity','Branding','Payload','Database','Registration','Maintenance','Scope','Presentation','Wizard','Semantics','Authoring','Inspection')) { . "$engine/$name.ps1" }
$output=Resolve-MsiPath $OutputDirectory
if(Test-Path -LiteralPath $output) { throw 'OutputDirectory must be new.' }
$null=New-Item -ItemType Directory -Path "$output/payload" -Force
$tag=[guid]::NewGuid().ToString('N').Substring(0,12)
$name='WBT Acceptance '+$tag
$folder='WbtAcceptance-'+$tag
Copy-Item -LiteralPath "$PSHOME/pwsh.exe" -Destination "$output/payload/Example.exe"
$config=Read-MsiConfiguration "$engine/example-v2.json"
$config.product.id='wbt-acceptance';$config.product.name=$name;$config.product.manufacturer='WBT Synthetic Acceptance'
$config.product.upgradeCode=[guid]::NewGuid().ToString('B').ToUpperInvariant()
$config.application=@{executable='Example.exe';appUserModelId=('WbtAcceptance.'+$tag)}
$config.architecture=if([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') {'ARM64'}else{'x64'}
$config.installation.directoryName=$folder;$config.installation.menuDirectoryName=$folder
$config.installation.scope='choice';$config.installation.defaultScope=$Scope;$config.installation.restartManager='disabled'
$config.ui=@{allowDirectoryChange=$true}
$config.shortcuts=@(@{name=$name;location='startMenu'})
$config.payload=@{requiredFiles=@('Example.exe','Data.txt');allowedExtensions=@('.exe','.txt');allowedFiles=@()}
$config.components=@{'Example.exe'=[guid]::NewGuid().ToString('B').ToUpperInvariant();'Data.txt'=[guid]::NewGuid().ToString('B').ToUpperInvariant()}
$packages=[Collections.Generic.List[object]]::new()
foreach($version in @('1.0.0','1.1.0')) {
 $config.product.productCode=[guid]::NewGuid().ToString('B').ToUpperInvariant()
 [IO.File]::WriteAllText("$output/payload/Data.txt",$version)
 $config | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath "$output/config-$version.json" -Encoding utf8NoBOM
 $validated=Read-MsiConfiguration "$output/config-$version.json"
 $path="$output/acceptance-$version.msi"
 New-MsiPackage $validated "$output/payload" $path $version $config.architecture
 Assert-MsiContents $path "$output/payload" $validated $version $config.architecture "$output/inspect-$version"
 $packages.Add([pscustomobject]@{Version=$version;ProductCode=$config.product.productCode;Artifact=$path})
}
$installRoot=if($Scope -eq 'user') { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('Programs/'+$folder+'-custom') } else { Join-Path $env:ProgramFiles ($folder+'-custom') }
if(Test-Path -LiteralPath $installRoot) { throw 'Synthetic install directory unexpectedly exists.' }
$manifest=[pscustomobject]@{Synthetic=$true;Name=$name;Scope=$Scope;Architecture=$config.architecture;UpgradeCode=$config.product.upgradeCode;InstallDirectory=$installRoot;Packages=$packages.ToArray();LifecycleRun=[bool]$RunLifecycle}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$output/acceptance.json" -Encoding utf8NoBOM
if(!$RunLifecycle) { $manifest;return }
function Invoke-FixtureMsi([string]$Arguments,[string]$Step,[int[]]$Accept=@(0,3010)) {
 $log=Join-Path $output ($Step+'.log')
 $command=$Arguments+' /qn /norestart /L*v "'+$log+'"'
 $process=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32/msiexec.exe') -ArgumentList $command -WindowStyle Hidden -Wait -PassThru
 if($process.ExitCode -notin $Accept) { throw "Synthetic $Step failed, exit $($process.ExitCode). Log: $log" }
 [pscustomobject]@{Step=$Step;ExitCode=$process.ExitCode;Log=$log}
}
$perUser=if($Scope -eq 'user') {'1'}else{'""'}
$results=[Collections.Generic.List[object]]::new()
try {
 $first=$packages[0];$second=$packages[1]
 $results.Add((Invoke-FixtureMsi ('/i "'+$first.Artifact+'" ALLUSERS=2 MSIINSTALLPERUSER='+$perUser+' INSTALLFOLDER="'+$installRoot+'"') install))
 if(!(Test-Path -LiteralPath "$installRoot/Data.txt")) { throw 'Synthetic installation did not use the requested custom directory.' }
 # This exact owned test file is intentionally removed to prove real repair.
 $target=[IO.Path]::GetFullPath((Join-Path $installRoot 'Data.txt'))
 if([IO.Path]::GetDirectoryName($target) -ine [IO.Path]::GetFullPath($installRoot) -or [IO.Path]::GetFileName($target) -cne 'Data.txt') {throw 'Unsafe repair fixture path.'}
 Remove-Item -LiteralPath $target -Force
 $results.Add((Invoke-FixtureMsi ('/fa '+$first.ProductCode) repair))
 if((Get-Content -LiteralPath "$installRoot/Data.txt" -Raw) -cne '1.0.0') { throw 'Repair did not restore fixture data.' }
 $results.Add((Invoke-FixtureMsi ('/i "'+$second.Artifact+'" ALLUSERS=2 MSIINSTALLPERUSER='+$perUser) upgrade))
 if((Get-Content -LiteralPath "$installRoot/Data.txt" -Raw) -cne '1.1.0') { throw 'Upgrade did not preserve the custom directory and update fixture bytes.' }
 $results.Add((Invoke-FixtureMsi ('/x '+$second.ProductCode) uninstall))
 if(Test-Path -LiteralPath "$installRoot/Example.exe") { throw 'Removal left the synthetic installed executable.' }
 $results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$output/lifecycle-results.json" -Encoding utf8NoBOM
 $manifest
} finally {
 # Only this invocation's random test GUIDs are eligible for cleanup. No input
 # product GUID is accepted from the caller or an existing manifest.
 foreach($package in $packages) { Invoke-FixtureMsi ('/x '+$package.ProductCode) ('cleanup-'+$package.Version) @(0,1605,3010) | Out-Null }
}
