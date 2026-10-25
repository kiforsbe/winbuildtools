#requires -Version 7.4

<#
.SYNOPSIS
Strict JSON and path validation for the standalone MSI engine.
.DESCRIPTION
Dot-source before Payload.ps1/Authoring.ps1. Read-MsiConfiguration returns the
validated hashtable; schema validation and semantic checks are both required.
Keep this file independent of ../common so copying msi/ remains supported.
#>
function Resolve-MsiPath([string]$Path) {
    # PowerShell Set-Location does not update .NET's process current directory.
    # The provider API also resolves destinations that do not exist yet.
    $provider=$null; $drive=$null
    $resolved=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path,[ref]$provider,[ref]$drive)
    if($provider.Name -ne 'FileSystem') { throw 'MSI paths must use the filesystem provider.' }
    return [IO.Path]::GetFullPath($resolved)
}
function Assert-MsiRelativePath([string]$Path) {
    # Refuse device/stream syntax and ambiguous names instead of rewriting paths.
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\x00-\x1f:"%<>|?*]' -or [IO.Path]::IsPathRooted($Path)) { throw "Invalid payload path: $Path" }
    foreach($part in $Path.Replace('\','/').Split('/')) {
        if(!$part -or $part -in @('.','..') -or $part -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)') { throw "Invalid path segment: $Path" }
    }
}
function Read-MsiConfiguration([string]$Path) {
    # The schema owns field types/allowed keys; the checks below additionally
    # enforce Windows naming rules and relationships the schema cannot express.
    $json=[IO.File]::ReadAllText((Resolve-MsiPath $Path))
    # ConvertFrom-Json keeps the last duplicate property; inspect original syntax first.
    $document=[Text.Json.JsonDocument]::Parse($json)
    function Assert-UniqueJsonKeys($Node) {
        # Compare case-insensitively to agree with PowerShell hashtable lookup;
        # reject duplicates at every nesting level before conversion loses them.
        if($Node.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach($p in $Node.EnumerateObject()) { if(!$seen.Add($p.Name)) { throw "Duplicate JSON property: $($p.Name)" }; Assert-UniqueJsonKeys $p.Value }
        } elseif($Node.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
            foreach($n in $Node.EnumerateArray()) { Assert-UniqueJsonKeys $n }
        }
    }
    try { Assert-UniqueJsonKeys $document.RootElement } finally { $document.Dispose() }
    $config=$json | ConvertFrom-Json -AsHashtable
    if($config.schemaVersion -isnot [long] -and $config.schemaVersion -isnot [int]) { throw 'schemaVersion must be an integer.' }
    $schema=switch($config.schemaVersion) {1 {'config.schema.json'} 2 {'config-v2.schema.json'} default {throw 'Unsupported MSI schemaVersion.'}}
    if(!($json | Test-Json -SchemaFile (Join-Path $PSScriptRoot $schema) -ErrorAction Stop)) { throw 'Invalid MSI configuration.' }
    if($config.schemaVersion -eq 2) {
        Assert-MsiRelativePath $config.installation.menuDirectoryName
        if($config.installation.menuDirectoryName -match '[/\\]') { throw 'menuDirectoryName must be one segment.' }
        if(($config.installation.scope -eq 'choice') -ne $config.installation.ContainsKey('defaultScope')) { throw 'defaultScope is required only for choice scope.' }
        # Persistent identities belong to the consumer. Normalize paths once and
        # reject aliases/collisions rather than silently choosing a map entry.
        $guids=[Collections.Generic.HashSet[guid]]::new()
        $map=@{}
        foreach($value in @($config.product.productCode,$config.product.upgradeCode)+@($config.components.Values)) {
            $guid=[guid]$value
            if($guid -eq [guid]::Empty -or !$guids.Add($guid)) { throw 'V2 identities must be nonzero, unique GUIDs.' }
        }
        foreach($key in $config.components.Keys) {
            Assert-MsiRelativePath $key
            $normalized=$key.Replace('\','/')
            if($map.ContainsKey($normalized)) { throw 'Duplicate normalized component path.' }
            $map[$normalized]=([guid]$config.components[$key]).ToString('B').ToUpperInvariant()
        }
        $config.components=$map
        foreach($name in @('productCode','upgradeCode')) { $config.product[$name]=([guid]$config.product[$name]).ToString('B').ToUpperInvariant() }
    }
    Assert-MsiRelativePath $config.installation.directoryName
    if($config.installation.directoryName -match '[/\\]') { throw 'Installation directoryName must be one segment.' }
    foreach($path in @($config.application.executable)+@($config.application.icon)+@($config.payload.requiredFiles)+@($config.payload.allowedFiles)) {
        if($path) { Assert-MsiRelativePath $path }
    }
    if([IO.Path]::GetExtension($config.application.executable) -ine '.exe') { throw 'Application executable must be an .exe.' }
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($shortcut in $config.shortcuts) {
        Assert-MsiRelativePath $shortcut.name
        if($shortcut.name -match '[/\\]' -or $shortcut.name.Length -gt 64 -or !$names.Add($shortcut.name)) { throw 'Invalid or duplicate shortcut name.' }
    }
    foreach($value in @($config.product.name,$config.product.manufacturer)) {
        if($value.Length -gt 64 -or $value -match '[\x00-\x1f]') { throw 'Product display fields must contain 1..64 printable characters.' }
    }
    $ui=if($config.ui) {$config.ui}else{@{}}
    $completion=if($ui.completion) {$ui.completion}else{@{}}
    if($completion.launchApplicationChecked -and !$completion.launchApplication) { throw 'launchApplicationChecked requires launchApplication.' }
    foreach($name in @('logo','sidebarImage')) {
        $asset=$ui[$name]
        if(!$asset) { continue }
        Assert-MsiRelativePath $asset
        $extensions=if($name -eq 'logo') {@('.ico','.png','.jpg','.jpeg','.bmp')}else{@('.png','.jpg','.jpeg','.bmp')}
        if([IO.Path]::GetExtension($asset) -notin $extensions) { throw "Unsupported UI image format: $name." }
    }
    if($config.ui.sidebarImage -and $config.ui.layout -cne 'brandedSidebar') { throw 'sidebarImage requires layout brandedSidebar.' }
    if($config.ui.showBrowseButton -and !$config.ui.allowDirectoryChange) { throw 'showBrowseButton requires allowDirectoryChange.' }
    foreach($name in @('releaseNotesUrl','helpUrl')) {
        $value=$completion[$name]
        if(!$value) { continue }
        $uri=$null
        # Links are consumer data, never MSI property references, credentials or
        # shell commands. The author separately escapes HTML attribute syntax.
        if($value -match '[\x00-\x20\[\]"<>\\]' -or ![uri]::TryCreate($value,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -cne 'https' -or !$uri.Host -or $uri.UserInfo) { throw "UI link must be a literal HTTPS URL without credentials: $name." }
    }
    foreach($value in $config.ui.completion.messages.Values) {
        if([string]::IsNullOrWhiteSpace($value) -or $value -match '[\x00-\x1f]') { throw 'Completion messages must be printable plain text.' }
    }
    return $config
}
