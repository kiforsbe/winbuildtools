#requires -Version 7.4
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
    $pathValue=(Resolve-WbtPath $Path).TrimEnd('\','/')
    $treeValue=(Resolve-WbtPath $Tree).TrimEnd('\','/')
    if($pathValue.Equals($treeValue,[StringComparison]::OrdinalIgnoreCase) -or $pathValue.StartsWith($treeValue+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Output must be outside the input tree.' }
}
function Get-WbtPayloadFiles([string]$Directory) {
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
