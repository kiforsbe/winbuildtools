#requires -Version 7.4

<#
.SYNOPSIS
Check source provenance, licenses, documentation links, CLI help and manual CI.
.DESCRIPTION
Reads repository files without fetching upstream sources or running the hosted
workflow. SHA256 entries describe current local files; ExtractionSHA256, when
present, preserves their original extraction hashes after documented local edits.
Link checks verify local targets, not Markdown anchors or remote availability.
#>
. "$PSScriptRoot/TestSupport.ps1"
$root=Split-Path $PSScriptRoot -Parent
$provenance=Get-Content "$root/docs/provenance.json" -Raw | ConvertFrom-Json
foreach($file in $provenance.Files) {
    Check ((Get-FileHash -LiteralPath (Join-Path $root $file.Path)).Hash -ceq $file.SHA256) "Extracted source changed without provenance update: $($file.Path)"
}
Check ((Get-Content "$root/LICENSE" -Raw).StartsWith('MIT License')) 'Root MIT license.'
Check ((Get-Content "$root/LICENSE" -Raw) -ceq (Get-Content "$root/msi/LICENSE" -Raw)) 'Standalone engine MIT license matches.'
Check (!(Get-Content "$root/LICENSE" -Raw).Contains('[fullname]')) 'Copyright placeholder filled.'
# Follow local document paths relative to each containing file. Fragment-only
# and web links have separate validation responsibilities and are skipped here.
$links=0
foreach($file in Get-ChildItem $root -Filter '*.md' -File -Recurse | Where-Object { $_.FullName -notmatch '[\\/](\.git|artifacts|work)[\\/]' }) {
    foreach($match in [regex]::Matches((Get-Content -LiteralPath $file.FullName -Raw),'\[[^\]]+\]\(([^)]+)\)')) {
        $target=$match.Groups[1].Value
        if($target -match '^(https?://|#)') { continue }
        $target=($target -split '#')[0]
        Check (Test-Path -LiteralPath (Join-Path $file.DirectoryName $target)) "Broken documentation link in $($file.Name): $target"
        $links++
    }
}
foreach($path in @('msi/package.ps1','msix/package.ps1','msix/inspect.ps1','signing/sign.ps1','signing/verify.ps1','common/write-artifact-manifest.ps1','dotnet/invoke.ps1','verify.ps1')) {
    $help=Get-Help (Join-Path $root $path)
    Check (![string]::IsNullOrWhiteSpace($help.Synopsis)) "Public help missing: $path"
}
# The workflow deliberately owns no Actions package tree and must stay manual.
# These checks do not prove hosted execution or GitHub repository settings.
$workflow=Get-Content "$root/.github/workflows/verify.yml" -Raw
$events=[regex]::Match($workflow,'(?ms)^on:\s*\r?\n(?<events>.*?)(?=^\S|\z)').Groups['events'].Value.Trim()
Check ($events -eq 'workflow_dispatch:') 'All workflow runs must be manual.'
Check ($workflow -notmatch '(?m)^\s*uses:') 'No third-party Actions dependency tree.'
Check ($workflow -match '(?m)^\s+contents: read\s*$') 'Minimal workflow permission.'
# Parse the embedded checkout script without executing authentication or network.
$script=[regex]::Match($workflow,'(?ms)        run: \|\r?\n(?<script>.*?)(?=      - name:)').Groups['script'].Value
$script=($script -split '\r?\n' | ForEach-Object { $_ -replace '^          ','' }) -join "`n"
$tokens=$null; $errors=$null
$null=[Management.Automation.Language.Parser]::ParseInput($script,[ref]$tokens,[ref]$errors)
Check (!$errors -and $script.Contains('GIT_CONFIG_VALUE_0')) 'Workflow checkout script parses.'
Write-Host "Repository/provenance/help/manual-CI checks passed; $links local documentation links."
