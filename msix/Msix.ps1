#requires -Version 7.4
. (Join-Path $PSScriptRoot '../common/Tools.ps1')
function Read-WbtMsixManifest([string]$Manifest) {
    $path=Resolve-WbtPath $Manifest
    Assert-WbtNoLinks $path
    # Caller manifests are data, not executable XML. Never resolve external DTDs.
    $settings=[Xml.XmlReaderSettings]::new(); $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit; $settings.XmlResolver=$null
    $reader=[Xml.XmlReader]::Create($path,$settings)
    try { $xml=[Xml.XmlDocument]::new(); $xml.XmlResolver=$null; $xml.Load($reader) } finally { $reader.Dispose() }
    $identity=$xml.DocumentElement.SelectSingleNode("*[local-name()='Identity']")
    if($xml.DocumentElement.LocalName -ne 'Package' -or !$identity -or !$identity.GetAttribute('Name') -or !$identity.GetAttribute('Publisher') -or $identity.GetAttribute('Version') -notmatch '^\d+\.\d+\.\d+\.\d+$' -or $identity.GetAttribute('ProcessorArchitecture') -notin @('x64','arm64','x86','neutral')) { throw 'Invalid MSIX manifest identity.' }
    [pscustomobject]@{Name=$identity.GetAttribute('Name');Publisher=$identity.GetAttribute('Publisher');Version=$identity.GetAttribute('Version');Architecture=$identity.GetAttribute('ProcessorArchitecture')}
}
function Get-WbtMsixPayload([string]$PayloadDirectory) {
    $files=@(Get-WbtPayloadFiles $PayloadDirectory)
    # Do not silently pack stale signatures/block maps or replace an input
    # manifest. Supply the authoritative manifest separately.
    foreach($file in $files) {
        $name=$file.Relative.Replace('\','/')
        if($name -in @('AppxManifest.xml','AppxBlockMap.xml','[Content_Types].xml','AppxSignature.p7x') -or $name -like 'AppxMetadata/*') { throw "Payload contains reserved MSIX metadata: $name" }
    }
    $files
}
function Test-WbtMsix {
    param([string]$Artifact,[string]$PayloadDirectory,[string]$Manifest,[string]$OutputDirectory)
    $artifactPath=Resolve-WbtPath $Artifact; $payload=Resolve-WbtPath $PayloadDirectory; $output=Resolve-WbtPath $OutputDirectory; $manifestPath=Resolve-WbtPath $Manifest
    Assert-WbtNoLinks $artifactPath; Assert-WbtNoLinks $output
    Assert-WbtOutsideTree $output $payload
    if(Test-Path -LiteralPath $output) { throw 'Inspection output already exists.' }
    $expected=Read-WbtMsixManifest $manifestPath
    $files=@(Get-WbtMsixPayload $payload)
    $null=New-Item -ItemType Directory -Path $output
    $extracted=Join-Path $output 'unpacked'
    Invoke-WbtTool (Get-WbtSdkTool makeappx.exe) @('unpack','/p',$artifactPath,'/d',$extracted,'/no') (Join-Path $output 'tool-output.log')
    $actual=Read-WbtMsixManifest (Join-Path $extracted 'AppxManifest.xml')
    foreach($field in @('Name','Publisher','Version','Architecture')) { if($actual.$field -cne $expected.$field) { throw "MSIX identity mismatch: $field" } }
    # MakeAppx may serialize the manifest, so compare canonical XML instead of
    # formatting bytes; all actual payload files are compared byte-for-byte.
    Add-Type -AssemblyName System.Security.Cryptography.Xml
    function Get-CanonicalManifest([string]$Path) {
        $doc=[Xml.XmlDocument]::new(); $doc.PreserveWhitespace=$false; $doc.XmlResolver=$null; $doc.Load($Path)
        $transform=[Security.Cryptography.Xml.XmlDsigC14NTransform]::new(); $transform.LoadInput($doc)
        $stream=$transform.GetOutput([IO.Stream]); $buffer=[IO.MemoryStream]::new()
        try { $stream.CopyTo($buffer); [Convert]::ToBase64String($buffer.ToArray()) } finally { $stream.Dispose(); $buffer.Dispose() }
    }
    if((Get-CanonicalManifest $manifestPath) -cne (Get-CanonicalManifest (Join-Path $extracted 'AppxManifest.xml'))) { throw 'MSIX manifest mismatch.' }
    $expectedNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($file in $files) {
        $null=$expectedNames.Add($file.Relative)
        $unpacked=Join-Path $extracted $file.Relative
        if(!(Test-Path -LiteralPath $unpacked -PathType Leaf) -or (Get-FileHash -LiteralPath $unpacked).Hash -ne (Get-FileHash -LiteralPath $file.Path).Hash) { throw "MSIX payload mismatch: $($file.Relative)" }
    }
    foreach($file in Get-WbtPayloadFiles $extracted) {
        $relative=$file.Relative.Replace('\','/')
        if($relative -in @('AppxManifest.xml','AppxBlockMap.xml','[Content_Types].xml','AppxSignature.p7x','AppxMetadata/CodeIntegrity.cat')) { continue }
        if(!$expectedNames.Contains($file.Relative)) { throw "Unexpected MSIX payload file: $relative" }
    }
    [pscustomobject]@{Artifact=$artifactPath;Name=$actual.Name;Publisher=$actual.Publisher;Version=$actual.Version;Architecture=$actual.Architecture;SHA256=(Get-FileHash -LiteralPath $artifactPath).Hash;InspectionDirectory=$output}
}
function New-WbtMsix {
    param([string]$PayloadDirectory,[string]$Manifest,[string]$OutputDirectory)
    $payload=Resolve-WbtPath $PayloadDirectory; $output=Resolve-WbtPath $OutputDirectory; $manifestPath=Resolve-WbtPath $Manifest
    Assert-WbtNoLinks $output; Assert-WbtOutsideTree $output $payload
    if(Test-Path -LiteralPath $output) { throw 'Package output already exists.' }
    $null=Read-WbtMsixManifest $manifestPath
    $files=@(Get-WbtMsixPayload $payload)
    $null=New-Item -ItemType Directory -Path (Join-Path $output 'stage')
    $stage=Join-Path $output 'stage'
    foreach($file in $files) {
        $target=Join-Path $stage $file.Relative
        $null=New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force
        Copy-Item -LiteralPath $file.Path -Destination $target
    }
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $stage 'AppxManifest.xml')
    $artifact=Join-Path $output 'package-unsigned.msix'
    Invoke-WbtTool (Get-WbtSdkTool makeappx.exe) @('pack','/d',$stage,'/p',$artifact,'/no') (Join-Path $output 'tool-output.log')
    $result=Test-WbtMsix $artifact $payload $manifestPath (Join-Path $output 'inspection')
    $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'inspection.json') -Encoding utf8NoBOM
    $result
}
