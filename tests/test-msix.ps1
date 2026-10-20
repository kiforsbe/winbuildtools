#requires -Version 7.4
. "$PSScriptRoot/TestSupport.ps1"
$root=Split-Path $PSScriptRoot -Parent
if(Test-Path "$root/msix/Msix.ps1") { . "$root/msix/Msix.ps1" }
Check ([bool](Get-Command New-WbtMsix -ErrorAction SilentlyContinue)) 'Missing generic MSIX packer.'
$fixture=New-TestDirectory
$null=New-Item -ItemType Directory -Path "$fixture/payload/Assets" -Force
try {
    [IO.File]::WriteAllText("$fixture/payload/Example.exe",'Synthetic executable; never installed.')
    # A real PNG and a caller-owned manifest; no Agenda dependency.
    Add-Type -AssemblyName System.Drawing
    $bitmap=[Drawing.Bitmap]::new(150,150)
    try { $bitmap.Save("$fixture/payload/Assets/Logo.png",[Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
    $manifest=@'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10" xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10" xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities" IgnorableNamespaces="uap rescap">
 <Identity Name="Winbuildtools.Example" Publisher="CN=Example" Version="1.2.3.0" ProcessorArchitecture="x64"/>
 <Properties><DisplayName>Example</DisplayName><PublisherDisplayName>Example</PublisherDisplayName><Logo>Assets/Logo.png</Logo></Properties>
 <Resources><Resource Language="en-us"/></Resources>
 <Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.22000.0" MaxVersionTested="10.0.26100.0"/></Dependencies>
 <Applications><Application Id="App" Executable="Example.exe" EntryPoint="Windows.FullTrustApplication"><uap:VisualElements DisplayName="Example" Description="Synthetic test" BackgroundColor="transparent" Square150x150Logo="Assets/Logo.png" Square44x44Logo="Assets/Logo.png"/></Application></Applications>
 <Capabilities><rescap:Capability Name="runFullTrust"/></Capabilities>
</Package>
'@
    [IO.File]::WriteAllText("$fixture/manifest.xml",$manifest)
    $before=(Get-FileHash "$fixture/payload/Example.exe").Hash
    Push-Location $fixture
    try { $result=& "$root/msix/package.ps1" -PayloadDirectory './payload' -Manifest './manifest.xml' -OutputDirectory './output with spaces' } finally { Pop-Location }
    Check (Test-Path $result.Artifact) 'MSIX produced.'
    Check ((Get-FileHash "$fixture/payload/Example.exe").Hash -eq $before -and !(Test-Path "$fixture/payload/AppxManifest.xml")) 'Input payload unchanged.'
    Check ((Get-AuthenticodeSignature $result.Artifact).Status -eq 'NotSigned') 'MSIX unsigned by default.'
    $check=& "$root/msix/inspect.ps1" -Artifact $result.Artifact -PayloadDirectory "$fixture/payload" -Manifest "$fixture/manifest.xml" -OutputDirectory "$fixture/second inspection"
    Check ($check.Publisher -eq 'CN=Example' -and $check.Version -eq '1.2.3.0') 'Manifest identity retained.'
    Rejected { New-WbtMsix "$fixture/payload" "$fixture/manifest.xml" "$fixture/output with spaces" } 'exist'
    Rejected { New-WbtMsix "$fixture/payload" "$fixture/manifest.xml" "$fixture/payload/output" } 'outside'
    Set-Content "$fixture/payload/extra.txt" 'unexpected input'
    Rejected { Test-WbtMsix $result.Artifact "$fixture/payload" "$fixture/manifest.xml" "$fixture/extra inspection" } 'payload'
    Remove-Item -LiteralPath "$fixture/payload/extra.txt"
    Move-Item -LiteralPath "$fixture/payload/Example.exe" -Destination "$fixture/held.exe"
    try { Rejected { Test-WbtMsix $result.Artifact "$fixture/payload" "$fixture/manifest.xml" "$fixture/unexpected inspection" } 'Unexpected MSIX payload' }
    finally { Move-Item -LiteralPath "$fixture/held.exe" -Destination "$fixture/payload/Example.exe" }
    [IO.File]::WriteAllText("$fixture/arm64.xml",$manifest.Replace('ProcessorArchitecture="x64"','ProcessorArchitecture="arm64"'))
    $arm64=New-WbtMsix "$fixture/payload" "$fixture/arm64.xml" "$fixture/arm64 package"
    Check ($arm64.Architecture -eq 'arm64') 'ARM64 manifest packs and inspects without executing.'
    [IO.File]::WriteAllText("$fixture/dtd.xml",$manifest.Replace('<Package ','<!DOCTYPE Package [<!ENTITY example "x">]><Package '))
    Rejected { New-WbtMsix "$fixture/payload" "$fixture/dtd.xml" "$fixture/dtd output" } 'DTD'
    Set-Content "$fixture/payload/Example.exe" 'changed'
    Rejected { Test-WbtMsix $result.Artifact "$fixture/payload" "$fixture/manifest.xml" "$fixture/changed inspection" } 'mismatch'
    Set-Content "$fixture/payload/AppxSignature.p7x" 'stale signature'
    Rejected { New-WbtMsix "$fixture/payload" "$fixture/manifest.xml" "$fixture/stale output" } 'metadata'
    Remove-Item -LiteralPath "$fixture/payload/AppxSignature.p7x"
    $null=New-Item -ItemType Junction -Path "$fixture/link" -Target "$fixture/payload"
    Rejected { New-WbtMsix "$fixture/link" "$fixture/manifest.xml" "$fixture/link output" } 'link'
    Remove-Item -LiteralPath "$fixture/link"
    Write-Host 'MSIX roundtrip and rejection checks passed (synthetic, not installed).'
} finally { Remove-TestDirectory $fixture }
