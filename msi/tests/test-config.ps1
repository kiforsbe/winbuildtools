#requires -Version 7.4

<#
.SYNOPSIS
Exercise strict MSI configuration, identity scoping and payload approval rules.
.DESCRIPTION
Standalone engine test: uses only msi/ helpers, not repository test support.
Synthetic files and a temporary junction exercise validation without authoring or
installing an MSI. Assertions fail immediately and cleanup validates its target.
#>
$ErrorActionPreference='Stop'
$engine=Split-Path $PSScriptRoot -Parent
if(Test-Path "$engine/Configuration.ps1") { . "$engine/Configuration.ps1"; . "$engine/Identity.ps1"; . "$engine/Branding.ps1"; . "$engine/Payload.ps1" }
if(!(Get-Command Read-MsiConfiguration -ErrorAction SilentlyContinue)) { throw 'Missing configuration validation.' }
$script:checks=0
function Check([bool]$Value,[string]$Message) { if(!$Value) { throw $Message }; $script:checks++ }
function Rejected([scriptblock]$Action) { $failed=$false; try { & $Action | Out-Null } catch { $failed=$true }; Check $failed 'Expected invalid input rejection.' }
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('MsiConfig-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path "$fixture/payload/Assets" -Force
try {
 $json=Get-Content "$engine/example.json" -Raw
 $path="$fixture/config.json"
 $json | Set-Content $path
 $config=Read-MsiConfiguration $path
 Check ($config.schemaVersion -eq 1) 'Supported schema loads.'
 Push-Location $engine
 try {
  $relative=Read-MsiConfiguration 'example.json'
  Check ($relative.product.id -eq 'example') 'Config paths follow PowerShell current location.'
 } finally { Pop-Location }
 # Reparse a pristine configuration for each mutation so a rejection identifies
 # that specific rule, rather than a previous mutation left in the fixture.
 foreach($change in @(
  {param($x) $x.schemaVersion=2},
  {param($x) $x.extra='unknown'},
  {param($x) $x.product.upgradeCode='invalid'},
  {param($x) $x.installation.scope='user'},
  {param($x) $x.application.executable='../app.exe'},
  {param($x) $x.installation.directoryName='CON'},
  {param($x) $x.application.executable='app.exe:stream'},
  {param($x) $x.shortcuts[0].location='desktop'},
  {param($x) $x.product.name=12},
  {param($x) $x.shortcuts=@($x.shortcuts[0],$x.shortcuts[0])}
 )) {
  $obj=$json | ConvertFrom-Json -AsHashtable
  & $change $obj
  $obj | ConvertTo-Json -Depth 10 | Set-Content $path
  Rejected { Read-MsiConfiguration $path }
 }
 # Duplicate keys must be introduced in raw JSON: a hashtable would collapse them
 # before Read-MsiConfiguration could exercise its syntax-level duplicate check.
 $json.Replace('"schemaVersion": 1','"schemaVersion": 1, "schemaVersion": 1') | Set-Content $path
 Rejected { Read-MsiConfiguration $path }
 $json | Set-Content $path
 foreach($v in @('0.1.0','255.255.65534')) { Assert-MsiVersion $v; $script:checks++ }
 foreach($v in @('256.0.0','0.256.0','0.0.65535','01.0.0','1.0.0-preview','1.0.0.0')) { Rejected { Assert-MsiVersion $v } }
 # These are compatibility properties, not golden hash values: normalization is
 # stable within a product while architecture and product namespaces isolate it.
 $a=Get-MsiGuid $config.product.upgradeCode 'component/x64/app.exe'
 Check ($a -eq (Get-MsiGuid $config.product.upgradeCode 'COMPONENT/X64/APP.EXE')) 'Identities ignore path case.'
 Check ($a -ne (Get-MsiGuid $config.product.upgradeCode 'component/arm64/app.exe')) 'Architectures isolated.'
 Check ($a -ne (Get-MsiGuid ([guid]::NewGuid()) 'component/x64/app.exe')) 'Products isolated.'
 Rejected { Get-MsiPayload $config "$fixture/payload" 'x64' }
 [IO.File]::WriteAllText("$fixture/payload/Example.exe",'synthetic')
 [IO.File]::WriteAllText("$fixture/payload/Assets/Example.ico",'synthetic')
 $files=@(Get-MsiPayload $config "$fixture/payload" 'x64')
 Check ($files.Count -eq 2) 'Approved payload enumerated.'
 # V2 supplies resolved identities. Exact map coverage is a payload boundary.
 . "$engine/Database.ps1"
 Check ((Get-MsiPackageGuid $config x64 'product/0.1.0') -ceq '{1447845A-7E48-8F3D-947A-52B6BCDDEBC7}') 'Published v1 product identity remains stable.'
 Check ((Get-MsiPackageGuid $config x64 upgrade) -ceq '{EBF52447-F382-8D6D-919D-5BB8157F144F}') 'Published v1 upgrade identity remains stable.'
 $v2=$json | ConvertFrom-Json -AsHashtable
 $v2.schemaVersion=2; $v2.architecture='x64'
 $v2.product.productCode='{10000000-0000-4000-8000-000000000001}'
 $v2.components=@{'Example.exe'='{10000000-0000-4000-8000-000000000002}';'Assets/Example.ico'='{10000000-0000-4000-8000-000000000003}'}
 $v2.installation.scope='choice'; $v2.installation.defaultScope='user'
 $v2.installation.menuDirectoryName='Example menu'; $v2.installation.restartManager='disabled'
 $v2json=$v2 | ConvertTo-Json -Depth 10
 $v2json | Set-Content $path
 $resolvedV2=Read-MsiConfiguration $path
 Check (@(Get-MsiPayload $resolvedV2 "$fixture/payload" x64).Count -eq 2) 'Explicit v2 payload loads.'
 Check ((Get-MsiPackageGuid $resolvedV2 x64 'product/9.8.7') -ceq $v2.product.productCode) 'Supplied product identity is literal.'
 Check ((Get-MsiPackageGuid $resolvedV2 x64 upgrade) -ceq $v2.product.upgradeCode) 'Supplied upgrade identity is literal.'
 foreach($change in @(
  {param($x) $x.product.Remove('productCode')},
  {param($x) $x.product.productCode=[guid]::Empty.ToString('B')},
  {param($x) $x.components['Assets/Example.ico']=$x.components['Example.exe']},
  {param($x) $x.components['Assets\Example.ico']=[guid]::NewGuid().ToString('B')},
  {param($x) $x.components['../bad.exe']=[guid]::NewGuid().ToString('B')},
  {param($x) $x.architecture='x86'},
  {param($x) $x.installation.Remove('defaultScope')},
  {param($x) $x.installation.scope='machine'},
  {param($x) $x.installation.defaultScope='choice'},
  {param($x) $x.installation.restartManager='force'},
  {param($x) $x.installation.menuDirectoryName='nested/menu'},
  {param($x) $x.components.extra='invalid'}
 )) {
  $bad=$v2json | ConvertFrom-Json -AsHashtable; & $change $bad | Out-Null
  $bad | ConvertTo-Json -Depth 10 | Set-Content $path
  Rejected { Read-MsiConfiguration $path }
 }
 Rejected { Get-MsiPayload $resolvedV2 "$fixture/payload" ARM64 }
 $resolvedV2.components.Remove('Example.exe') | Out-Null
 Rejected { Get-MsiPayload $resolvedV2 "$fixture/payload" x64 }
 # Presentation inputs stay optional/strict; identity is consumer-owned and
 # license input is plain text rather than executable RTF content.
 $presentation=$v2json | ConvertFrom-Json -AsHashtable
 $presentation.ui=@{allowDirectoryChange=$true;licenseText='Example terms: {literal} \ Unicode å'}
 $presentation.application.appUserModelId='Example.App'
 $presentation.ui.layout='brandedSidebar'
 $presentation.ui.logo='Assets/Example.ico'
 $presentation.ui.sidebarImage='Assets/sidebar.png'
 $presentation.ui.showBrowseButton=$true
 $presentation.ui.completion=@{launchApplication=$true;launchApplicationChecked=$true;showDetails=$true;releaseNotesUrl='https://example.com/notes?a=1&b=2';helpUrl='https://example.com/help';messages=@{installed='Ready to use.';updated='Updated.';repaired='Repaired.';removed='Removed.';canceled='Canceled.';failed='Failed.';restartRequired='Restart Windows.'}}
 $presentation | ConvertTo-Json -Depth 10 | Set-Content $path
 $validatedPresentation=Read-MsiConfiguration $path
 Check ($validatedPresentation.ui.allowDirectoryChange -eq $true -and $validatedPresentation.application.appUserModelId -ceq 'Example.App') 'Optional presentation and application identity load.'
 $v1presentation=$json | ConvertFrom-Json -AsHashtable
 $v1presentation.ui=$presentation.ui | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
 $v1presentation.ui.layout='compactHeader';$v1presentation.ui.Remove('sidebarImage') | Out-Null
 $v1presentation | ConvertTo-Json -Depth 10 | Set-Content $path
 Check ((Read-MsiConfiguration $path).ui.layout -ceq 'compactHeader') 'V1 accepts the same bounded presentation options.'
 foreach($change in @(
  {param($x) $x.ui.allowDirectoryChange='yes'},
  {param($x) $x.ui.licenseText=''},
  {param($x) $x.ui.extra='unknown'},
  {param($x) $x.application.appUserModelId='invalid id with spaces'},
  {param($x) $x.ui.layout='web'},
  {param($x) $x.ui.logo='../logo.png'},
  {param($x) $x.ui.logo='Assets/logo.exe'},
  {param($x) $x.ui.layout='compactHeader'},
  {param($x) $x.ui.allowDirectoryChange=$false},
  {param($x) $x.ui.completion.launchApplication='yes'},
  {param($x) $x.ui.completion.launchApplicationChecked='yes'},
  {param($x) $x.ui.completion.launchApplication=$false},
  {param($x) $x.ui.completion.Remove('launchApplication') | Out-Null},
  {param($x) $x.ui.completion.command='cmd.exe'},
  {param($x) $x.ui.completion.helpUrl='file:///C:/Windows/notepad.exe'},
  {param($x) $x.ui.completion.helpUrl='https://user:password@example.com/help'},
  {param($x) $x.ui.completion.helpUrl='https://example.com/[ProductCode]'},
  {param($x) $x.ui.completion.messages.installed="Bad`nmessage"},
  {param($x) $x.ui.completion.messages.installed=('a'*161)},
  {param($x) $x.ui.completion.messages.unknown='Ignored'}
 )) {
  $bad=$presentation | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
  & $change $bad
  $bad | ConvertTo-Json -Depth 10 | Set-Content $path
  Rejected { Read-MsiConfiguration $path }
 }
 $resolvedV2=$v2json | ConvertFrom-Json -AsHashtable
 $resolvedV2.components['extra.exe']=[guid]::NewGuid().ToString('B')
 Rejected { Get-MsiPayload $resolvedV2 "$fixture/payload" x64 }
 [IO.File]::WriteAllText("$fixture/payload/Assets/settings.json",'synthetic approved data')
 $config.payload.allowedFiles=@('Assets\settings.json')
 Check (@(Get-MsiPayload $config "$fixture/payload" 'x64').Count -eq 3) 'Backslash exact approvals match normalized payload paths.'
 Remove-Item "$fixture/payload/Assets/settings.json"
 [IO.File]::WriteAllText("$fixture/payload/credentials.json",'secret fixture')
 Rejected { Get-MsiPayload $config "$fixture/payload" 'x64' }
 Remove-Item "$fixture/payload/credentials.json"
 $junction="$fixture/linked"
 $null=New-Item -ItemType Junction -Path $junction -Target "$fixture/payload"
 Rejected { Get-MsiPayload $config $junction 'x64' }
 Remove-Item -LiteralPath $junction -Force
 Write-Host "Configuration checks passed: $checks"
} finally {
 $resolved=[IO.Path]::GetFullPath($fixture)
 if([IO.Path]::GetDirectoryName($resolved) -ne [IO.Path]::GetTempPath().TrimEnd('\') -or [IO.Path]::GetFileName($resolved) -notlike 'MsiConfig-*') { throw 'Unsafe test cleanup.' }
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
