#requires -Version 7.4

<#
.SYNOPSIS
Enumerate and approve a bounded payload for single-cabinet MSI authoring.
.DESCRIPTION
Requires Configuration.ps1 and Identity.ps1. Returns Id, Component, Relative,
FullName, Name and Length records after validating the entire file set. It does
not build or run the application, or decide whether approved content is safe.
#>
function Get-MsiPayload($Configuration,[string]$Folder,[ValidateSet('x64','ARM64')][string]$Architecture) {
    if($Configuration.schemaVersion -eq 2 -and $Configuration.architecture -ine $Architecture) { throw 'Configuration architecture mismatch.' }
    $Folder=Resolve-MsiPath $Folder
    $root=Get-Item -LiteralPath $Folder -Force
    if(!$root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Payload root must be a real directory.' }
    # Walk one level at a time: never descend through a link while checking descendants.
    $pending=[Collections.Generic.Queue[string]]::new(); $pending.Enqueue($Folder)
    $all=[Collections.Generic.List[IO.FileInfo]]::new()
    while($pending.Count) {
        foreach($item in Get-ChildItem -LiteralPath $pending.Dequeue() -Force) {
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Payload contains a link: $($item.Name)" }
            if($item.PSIsContainer) { $pending.Enqueue($item.FullName) } else { $all.Add($item) }
        }
    }
    # Cabinet member order and File.Sequence must agree in authoring/inspection.
    # Sorting by normalized relative name keeps that agreement independent of
    # filesystem enumeration order; case aliases are rejected separately.
    $files=@($all | Sort-Object { [IO.Path]::GetRelativePath($Folder,$_.FullName).ToLowerInvariant() })
    if(!$files.Count -or $files.Count -gt 10000 -or ($files | Measure-Object Length -Sum).Sum -gt 2GB) { throw 'Payload exceeds bounded single-cabinet limits.' }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $approved=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($name in $Configuration.payload.allowedFiles) { $null=$approved.Add($name.Replace('\','/')) }
    foreach($file in $files) {
        if($file.Length -gt [int]::MaxValue) { throw 'A payload file exceeds the MSI FileSize limit.' }
        $relative=[IO.Path]::GetRelativePath($Folder,$file.FullName).Replace('\','/')
        Assert-MsiRelativePath $relative
        if($file.FullName -match '[\r\n"%]' -or !$seen.Add($relative)) { throw 'Unsupported cabinet path or duplicate payload name.' }
        if([IO.Path]::GetExtension($relative) -notin $Configuration.payload.allowedExtensions -and !$approved.Contains($relative)) { throw "Unapproved payload file: $relative" }
    }
    # The executable/icon are implicitly required, even if omitted from the
    # explicit list. Validate everything before emitting any pipeline records.
    foreach($required in @($Configuration.payload.requiredFiles)+@($Configuration.application.executable)+@($Configuration.application.icon)) {
        if($required -and !$seen.Contains($required.Replace('\','/'))) { throw "Payload missing required file: $required" }
    }
    if($Configuration.schemaVersion -eq 2) {
        if($Configuration.components.Count -ne $seen.Count -or @($seen | Where-Object { !$Configuration.components.ContainsKey($_) }).Count) { throw 'Component map must cover exactly the approved payload paths.' }
    }
    foreach($file in $files) {
        $relative=[IO.Path]::GetRelativePath($Folder,$file.FullName).Replace('\','/')
        $ns=[guid]$Configuration.product.upgradeCode
        [pscustomobject]@{Id=(Get-MsiId 'F' $ns "$Architecture/$relative");Component=(Get-MsiId 'C' $ns "$Architecture/$relative");Relative=$relative;FullName=$file.FullName;Name=$file.Name;Length=$file.Length}
    }
}
