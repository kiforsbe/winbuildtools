#requires -Version 7.4

<#
.SYNOPSIS
Shared filesystem validation for MSIX, signing, manifests and .NET commands.
.DESCRIPTION
Dot-source this file; it performs no work until a function is called. Helpers
return resolved paths or payload records, or throw before a caller writes output.
The standalone MSI engine owns separate path validation under msi/.
#>
# Resolve through PowerShell's provider/location, not .NET's process directory.
# Destinations may not exist yet, but non-filesystem providers must be rejected.
function Resolve-WbtPath([string]$Path) {
    if([string]::IsNullOrWhiteSpace($Path)) { throw 'A filesystem path is required.' }
    $provider=$null; $drive=$null
    $resolved=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path,[ref]$provider,[ref]$drive)
    if($provider.Name -ne 'FileSystem') { throw 'Paths must use the filesystem provider.' }
    [IO.Path]::GetFullPath($resolved)
}
function Assert-WbtNoLinks([string]$Path) {
    # Check ancestors as well as the final item: a normal-looking child may be
    # reached through a junction. Do not follow links during payload enumeration.
    $current=Resolve-WbtPath $Path
    while($current) {
        if(Test-Path -LiteralPath $current) {
            if((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Links/reparse points are not supported: $current" }
        }
        $current=[IO.Path]::GetDirectoryName($current)
    }
}
function Assert-WbtOutsideTree([string]$Path,[string]$Tree) {
    # Include the separator in the prefix test so sibling names such as app-old
    # are not confused with children of app. Equality also counts as overlap.
    $pathValue=(Resolve-WbtPath $Path).TrimEnd('\','/')
    $treeValue=(Resolve-WbtPath $Tree).TrimEnd('\','/')
    if($pathValue.Equals($treeValue,[StringComparison]::OrdinalIgnoreCase) -or $pathValue.StartsWith($treeValue+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Output must be outside the input tree.' }
}
function Get-WbtPayloadFiles([string]$Directory) {
    # Return Relative/Path records for files only; empty directories are not a
    # payload contract. Validate each child before queueing it to avoid links.
    $root=Resolve-WbtPath $Directory
    Assert-WbtNoLinks $root
    if(!(Test-Path -LiteralPath $root -PathType Container)) { throw 'Payload directory not found.' }
    $queue=[Collections.Generic.Queue[string]]::new(); $queue.Enqueue($root)
    $files=[Collections.Generic.List[object]]::new()
    while($queue.Count) {
        foreach($item in Get-ChildItem -LiteralPath $queue.Dequeue() -Force) {
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Payload contains a link: $($item.FullName)" }
            if($item.PSIsContainer) { $queue.Enqueue($item.FullName) }
            else {
                if($files.Count -ge 10000) { throw 'Payload exceeds 10000 files.' }
                $files.Add([pscustomobject]@{Relative=[IO.Path]::GetRelativePath($root,$item.FullName);Path=$item.FullName})
            }
        }
    }
    $files.ToArray()
}
