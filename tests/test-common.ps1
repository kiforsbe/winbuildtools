#requires -Version 7.4
. "$PSScriptRoot/TestSupport.ps1"
$root=Split-Path $PSScriptRoot -Parent
if(Test-Path "$root/common/Tools.ps1") { . "$root/common/Tools.ps1"; . "$root/common/Artifacts.ps1" }
Check ([bool](Get-Command Invoke-WbtTool -ErrorAction SilentlyContinue)) 'Missing common tool runner.'
$fixture=New-TestDirectory
$null=New-Item -ItemType Directory -Path "$fixture/path with spaces" -Force
try {
    Push-Location $fixture
    try { Check ((Resolve-WbtPath './path with spaces/new') -eq "$fixture\path with spaces\new") 'Paths follow PowerShell location.' } finally { Pop-Location }
    $pwsh=(Get-Process -Id $PID).Path
    Invoke-WbtTool $pwsh @('-NoProfile','-Command',"Write-Output 'full diagnostics'; exit 0") "$fixture/tool.log"
    Check ((Get-Content "$fixture/tool.log" -Raw).Contains('full diagnostics')) 'Full tool log.'
    Rejected { Invoke-WbtTool $pwsh @('-NoProfile','-Command',"Write-Output 'failure detail'; exit 7") "$fixture/tool.log" } 'exit 7'
    Check ((Get-Content "$fixture/tool.log" -Raw).Contains('failure detail')) 'Failed tool log retained.'
    Rejected { Invoke-WbtTool "$fixture/missing.exe" @() } 'not found'
    Rejected { Resolve-WbtPath 'Env:PATH' } 'filesystem'
    Set-Content "$fixture/artifact.msi" 'final bytes'
    $result=Write-WbtArtifactManifest -Artifact "$fixture/artifact.msi" -OutputPath "$fixture/release.json" -Version 1.2.3 -SourceCommit ('a'*40)
    $record=Get-Content $result.Manifest -Raw | ConvertFrom-Json
    Check ($record.SHA256 -eq (Get-FileHash "$fixture/artifact.msi").Hash -and !$record.Signed) 'Final hash and unsigned metadata.'
    Rejected { Write-WbtArtifactManifest -Artifact "$fixture/artifact.msi" -OutputPath "$fixture/release.json" } 'exist'
    $sdk=Get-WbtSdkTool makeappx.exe
    Check (Test-Path $sdk) 'Installed SDK discovered.'
    Rejected { Get-WbtSdkTool makeappx.exe -SdkRoot "$fixture/missing" } 'SDK'
    Write-Host 'Common helper checks passed.'
} finally { Remove-TestDirectory $fixture }
