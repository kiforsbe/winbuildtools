#requires -Version 7.4

<#
.SYNOPSIS
MSI version limits and deterministic product/component identifier primitives.
.DESCRIPTION
Dot-source before payload enumeration and authoring. Identity scopes are a
compatibility contract: changing normalization or hash derivation changes the
identities seen by Windows Installer, even if the payload itself is unchanged.
#>
function Assert-MsiVersion([string]$Version) {
    # MSI ProductVersion uses three bounded numeric fields, without prerelease
    # suffixes or leading zeroes; a four-part Windows file version is not valid.
    if($Version -notmatch '^(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})$') { throw 'MSI version must be stable major.minor.patch.' }
    $v=[version]$Version
    if($v.Major -gt 255 -or $v.Minor -gt 255 -or $v.Build -gt 65534) { throw 'MSI version exceeds 255.255.65534.' }
}
# The permanent product GUID is the namespace. Scope includes architecture and
# normalized relative file path; renaming a file deliberately changes its component.
function Get-MsiGuid([guid]$Namespace,[string]$Scope) {
    $bytes=[Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Namespace.ToString('D')+'/'+$Scope.ToLowerInvariant().Replace('\','/')))
    # RFC 4122 variant/version bits; identities are deterministic SHA-256-derived UUIDs.
    $bytes[7]=($bytes[7] -band 15) -bor 128
    $bytes[8]=($bytes[8] -band 63) -bor 128
    return ([guid]::new([byte[]]$bytes[0..15])).ToString('B').ToUpperInvariant()
}
function Get-MsiId([string]$Prefix,[guid]$Namespace,[string]$Scope) {
    # Prefixes distinguish table identifier roles. GUID punctuation is removed
    # to produce a compact MSI identifier rather than an MSI GUID column value.
    return $Prefix+(Get-MsiGuid $Namespace $Scope).Replace('-','').Trim('{}')
}
