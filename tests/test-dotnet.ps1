#requires -Version 7.4
param([switch]$Integration)
. "$PSScriptRoot/TestSupport.ps1"
$root=Split-Path $PSScriptRoot -Parent
Check (Test-Path "$root/dotnet/invoke.ps1") 'Missing generic .NET helper.'
$fixture=New-TestDirectory
$null=New-Item -ItemType Directory -Path "$fixture/project with spaces" -Force
try {
    $helper="$root/dotnet/invoke.ps1"
    Rejected { & $helper -Operation Build -Project "$fixture/missing.csproj" -ArtifactsDirectory "$fixture/artifacts" } 'exist|find'
    Set-Content "$fixture/project with spaces/Example.csproj" '<Project Sdk="Microsoft.NET.Sdk"/>'
    Rejected { & $helper -Operation Restore -Project "$fixture/project with spaces/Example.csproj" -ArtifactsDirectory "$fixture/obj" -Properties @{'bad;property'='x'} } 'property'
    Rejected { & $helper -Operation Build -Project "$fixture/project with spaces/Example.csproj" -ArtifactsDirectory "$fixture/obj" -OutputDirectory "$fixture/output" } 'Publish'
    Rejected { & $helper -Operation Build -Project "$fixture/project with spaces/Example.csproj" -ArtifactsDirectory "$fixture/obj" -Properties @{ArtifactsPath='other'} } 'owned'
    Rejected { & $helper -Operation Restore -Project "$fixture/project with spaces/Example.csproj" -ArtifactsDirectory "$fixture/obj" -Properties @{Example='x,RestoreLockedMode=false'} } 'property'
    if($Integration) {
        $sdkOutput=& dotnet --version
        if($LASTEXITCODE -ne 0 -or $sdkOutput -notmatch '^\d+\.\d+\.\d+$') { throw 'A stable .NET 8+ SDK is required for integration tests.' }
        $major=([version]$sdkOutput).Major
        Check ($major -ge 8) 'SDK floor.'
        $project="$fixture/project with spaces/Example.csproj"
        [IO.File]::WriteAllText($project,"<Project Sdk=`"Microsoft.NET.Sdk`"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net$major.0</TargetFramework><RestorePackagesWithLockFile>true</RestorePackagesWithLockFile></PropertyGroup></Project>")
        Set-Content "$fixture/project with spaces/Program.cs" 'System.Console.WriteLine("fixture built");'
        # Generate only the dependency-free test fixture lock, as a consumer would
        # before committing it. The shared helper always restores in locked mode.
        & dotnet restore $project --artifacts-path "$fixture/artifacts" --use-lock-file *> "$fixture/initial-restore.log"
        Check ($LASTEXITCODE -eq 0) 'Fixture lock creation.'
        Push-Location $fixture
        try {
            Rejected { & $helper -Operation Build -Project './project with spaces/Example.csproj' -ArtifactsDirectory './never-restored' } 'failed'
            $null=& $helper -Operation Restore -Project './project with spaces/Example.csproj' -ArtifactsDirectory './artifacts' -Properties @{RestorePackagesWithLockFile='true'}
            $null=& $helper -Operation Build -Project './project with spaces/Example.csproj' -ArtifactsDirectory './artifacts'
            $result=& $helper -Operation Publish -Project './project with spaces/Example.csproj' -ArtifactsDirectory './artifacts' -OutputDirectory './published output' -LogPath './logs/publish.log'
            Check ($result.LogPath -eq "$fixture\logs\publish.log" -and (Test-Path "$fixture/logs/publish.log")) 'Explicit log path follows caller location.'
        } finally { Pop-Location }
        Check (Test-Path "$fixture/published output/Example.dll") 'Real publish output.'
        $run=& dotnet "$fixture/published output/Example.dll"
        Check ($LASTEXITCODE -eq 0 -and $run -eq 'fixture built') 'Published managed fixture executes.'
        Check ($result.Operation -eq 'Publish' -and (Test-Path $result.LogPath)) 'Structured build result and log.'
    }
    Write-Host ".NET helper checks passed; integration=$Integration."
} finally { Remove-TestDirectory $fixture }
