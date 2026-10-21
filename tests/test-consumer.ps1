#requires -Version 7.4

<#
.SYNOPSIS
Verify an independent consumer with a pinned recursively cloned tool submodule.
.DESCRIPTION
Requires Git and the native MSI prerequisites. Creates only disposable local Git
repositories, builds a synthetic MSI and never installs it. The cloned tool
revision is committed HEAD: uncommitted tool changes are not tested by the clone.
#>
. "$PSScriptRoot/TestSupport.ps1"
$root=Split-Path $PSScriptRoot -Parent
Check (Test-Path "$root/examples/consumer-package.ps1") 'Missing pinned-checkout consumer example.'
$fixture=New-TestDirectory
$null=New-Item -ItemType Directory -Path "$fixture/consumer/deployment" -Force
try {
    . "$root/common/Tools.ps1"
    $pwsh=(Get-Process -Id $PID).Path
    Copy-Item "$root/examples/consumer-package.ps1" "$fixture/consumer/package.ps1"
    Copy-Item "$root/msi/example.json" "$fixture/consumer/deployment/msi.json"
    Rejected { & "$fixture/consumer/package.ps1" -PayloadDirectory "$fixture/payload" -Version 2.3.4 -Architecture x64 -OutputDirectory "$fixture/no checkout" } 'submodule update --init --recursive'
    # The tested source must be committed so a consumer receives actual Git
    # content. Use a local file transport override only for these owned fixtures.
    $revision=(& git -C $root rev-parse HEAD).Trim()
    Invoke-WbtTool git @('init','--initial-branch=main',"$fixture/consumer")
    Invoke-WbtTool git @('-C',"$fixture/consumer",'config','user.name','Fixture')
    Invoke-WbtTool git @('-C',"$fixture/consumer",'config','user.email','fixture@example.invalid')
    Invoke-WbtTool git @('-C',"$fixture/consumer",'-c','protocol.file.allow=always','submodule','add',$root,'external/winbuildtools')
    Invoke-WbtTool git @('-C',"$fixture/consumer/external/winbuildtools",'checkout','--detach',$revision)
    Invoke-WbtTool git @('-C',"$fixture/consumer",'add','.')
    Invoke-WbtTool git @('-C',"$fixture/consumer",'commit','-m','Pin tool revision')
    Invoke-WbtTool git @('-c','protocol.file.allow=always','clone','--recurse-submodules',"$fixture/consumer","$fixture/fresh consumer with spaces")
    $consumer="$fixture/fresh consumer with spaces"
    $actual=(& git -C "$consumer/external/winbuildtools" rev-parse HEAD).Trim()
    Check ($actual -ceq $revision) 'Fresh recursive clone uses pinned revision.'
    $null=New-Item -ItemType Directory -Path "$fixture/payload/Assets" -Force
    Set-Content "$fixture/payload/Example.exe" 'synthetic consumer executable'
    Set-Content "$fixture/payload/Assets/Example.ico" 'synthetic consumer icon'
    # The consumer owns product metadata; change namespace as well as display
    # name so its components cannot share ownership with the example product.
    $config=Get-Content "$consumer/deployment/msi.json" -Raw | ConvertFrom-Json
    $config.product.id='consumer'; $config.product.name='Independent Consumer'; $config.product.upgradeCode=[guid]::NewGuid().ToString('B')
    $config | ConvertTo-Json -Depth 10 | Set-Content "$consumer/deployment/msi.json"
    # Invoke from another directory, through the actual pinned tool checkout.
    Push-Location $fixture
    try { $result=& "$consumer/package.ps1" -PayloadDirectory './payload' -Version 2.3.4 -Architecture x64 -OutputDirectory './consumer output' } finally { Pop-Location }
    Check ((Test-Path $result.Artifact) -and $result.SHA256 -eq (Get-FileHash $result.Artifact).Hash) 'Pinned external MSI build and inspection.'
    Check ([IO.Path]::GetFileName($result.Artifact) -eq 'consumer-2.3.4-x64.msi') 'Consumer metadata owns product/version.'
    Write-Host "Pinned recursive-checkout consumer passed at $revision."
} finally { Remove-TestDirectory $fixture }
