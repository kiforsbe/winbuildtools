# Dependencies and platform review

Reviewed against official upstream guidance on 2026-10-20. This repository adds
no NuGet, npm or PowerShell module packages and vendors no binary runtime/tool.
Its workflow uses no third-party Actions, so it adds no bundled Node transitive
dependency/license/advisory tree. This does not establish complete security.

| Input | Boundary and terms |
| --- | --- |
| Windows Installer Automation, MakeCab, Expand | Windows-provided components under the host's Windows terms; not redistributed here |
| Windows SDK MakeAppx/SignTool | Installed host prerequisite; SDK 10.0.26100.0+ discovery floor, not a latest-version claim or bundled copy |
| PowerShell | Installed 7.4+ API floor; consumers must use a supported stable release and its own license/notices |
| Git | Installed checkout tool; no Git distribution is bundled |
| .NET SDK | Optional, caller-installed supported stable SDK exposing .NET 8+ artifacts-path behavior; no runtime/SDK is bundled |
| GitHub-hosted Windows runner | Hosted infrastructure maintained by GitHub; installed software changes independently of this source |

These are interface/support floors, not pins or assertions that the minimum is
the latest release. This extraction did not select, install or upgrade platform
versions. Local native validation used Windows SDK 10.0.26100.0 and PowerShell
7.6.5. The real .NET fixture used an already-installed SDK 10.0.402. Production
consumers select their supported stable SDK/runtime set and review both direct
and transitive application/tool packages against live authoritative registries,
upstream deprecations/replacements, known advisories and actual redistribution
terms. Do not infer permission or safety from a familiar name or successful restore.

The application owns NuGet.Config, lock files, restore/audit severity policy,
package licenses, runtime notices and exceptions. The generic .NET helper uses
locked restore but does not claim that a lock or audit proves currency/security.
The dependency-free synthetic fixture has no PackageReference and uses the
installed SDK's matching framework. Test-generated locks are not application locks.

Sources used for interface/checkout decisions:

- [MakeAppx syntax and validation](https://learn.microsoft.com/en-us/windows/msix/package/create-app-package-with-makeappx-tool)
- [.NET publish](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-publish)
- [Git submodules](https://git-scm.com/docs/gitsubmodules)
- [Git process configuration](https://git-scm.com/docs/git-config)
- [GitHub workflow token](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token)
- [GitHub MIT template](https://github.com/github/choosealicense.com/blob/gh-pages/_licenses/mit.txt)

MIT covers this repository's source under the copyright holder's explicit
relicensing authorization. It does not relicense Microsoft platform components
or consumers' application payloads. Source provenance is in [NOTICE.md](../NOTICE.md).

## V2 integration review — 2026-10-23

Live origin refs were checked during this integration: main and the newest listed
version tag v0.3.0 both resolve to 9a3bf8cf1d79d05946abbd020fe57ccec3d0ceb5.
The published upstream MIT license and local matching root/standalone license
texts were reviewed; existing attribution and original extraction hashes remain.
This candidate adds source helpers only. It adds no NuGet/npm/PowerShell package,
third-party Action, binary redistribution or package transitive dependency tree;
there is therefore no new package registry/version/license set to select or scan.
Consumer application package/advisory/license review remains in that repository.

Live Microsoft guidance was checked for MSIINSTALLPERUSER/ALLUSERS, native property
events, installation-context folder redirection, summary privilege flags, certificate
content-type detection and object-based X509Store.Add. The byte certificate constructor
is retained for the supported PowerShell 7.4/.NET 8 API floor; newer certificate-loader
APIs cannot replace it without raising that floor. No platform was installed/upgraded
or selected by this change. Installed host versions are verification observations,
not latest-stable or vulnerability-free claims. Private/unpublished advisories and
host platform servicing status were not audited; no complete security claim is made.

- [Published source license](https://github.com/kiforsbe/winbuildtools/blob/v0.3.0/LICENSE)
- [MSI context properties](https://learn.microsoft.com/en-us/windows/win32/msi/msiinstallperuser)
- [Native property events](https://learn.microsoft.com/en-us/windows/win32/msi/setproperty-controlevent)
- [Installation context](https://learn.microsoft.com/en-us/windows/win32/msi/installation-context)
- [Summary flags](https://learn.microsoft.com/en-us/windows/win32/msi/word-count-summary)
- [Certificate content-type API](https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.x509certificates.x509certificate2.getcertcontenttype)
- [Object store import API](https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.x509certificates.x509store.add)

## Native wizard interface review — 2026-10-23

This change adds no package, module, Action, runtime or vendored binary, and has no
new package transitive dependency tree to review. It uses the installed Windows
Installer 5.0 COM engine/property store and platform user32/System.Drawing/WinForms
APIs for inactive native preview. No platform version is selected or upgraded.
Windows SDK `propkey.h` 10.0.26100.0 documents
`System.AppUserModel.UninstallCommand` (FMTID 9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3,
PID 37) for Start uninstall. The installed SDK preview example was read as API
reference, not copied or redistributed. Existing Windows/SDK terms still apply;
the source MIT license does not grant rights to fixture or platform binaries.

Live Microsoft guidance was checked for native shortcut properties, ARP location,
type-51 setters, progress mappings, discovery order, native repair/remove events,
preview lifetime and secure property transfer. EndDialog is full-UI-only; reduced
progress therefore disables its authored Cancel control. No host servicing audit,
platform advisory completeness or actual Start/lifecycle acceptance is claimed.

- [Shortcut property table](https://learn.microsoft.com/en-us/windows/win32/msi/msishortcutproperty-table)
- [ARP location](https://learn.microsoft.com/en-us/windows/win32/msi/arpinstalllocation)
- [Type-51 property setter](https://learn.microsoft.com/en-us/windows/win32/msi/custom-action-type-51)
- [Native progress](https://learn.microsoft.com/en-us/windows/win32/msi/authoring-a-progressbar-control)
- [Repair event](https://learn.microsoft.com/en-us/windows/win32/msi/reinstall-controlevent)
- [Remove event](https://learn.microsoft.com/en-us/windows/win32/msi/remove-controlevent)
- [Native preview](https://learn.microsoft.com/en-us/windows/win32/msi/previewing-the-user-interface)
- [Secure property transfer](https://learn.microsoft.com/en-us/windows/win32/msi/securecustomproperties)
- [EndDialog UI constraint](https://learn.microsoft.com/en-us/windows/win32/msi/enddialog-controlevent)

## Configurable presentation review — 2026-10-24

No package/runtime/tool version was selected, installed or upgraded. There is no
new package transitive dependency tree or redistributed binary. Image validation
uses the System.Drawing assembly already supplied with the installed PowerShell 7
runtime on Windows; this is Windows-only. Native MSI Binary/Bitmap/Icon/PathEdit/
DirectoryList/Hyperlink controls and MsiLaunchApp need no added installer library.
The host owns platform servicing and its Windows/runtime license terms; the source
MIT license does not relicense consumer artwork or platform components.

Live authoritative Microsoft guidance was checked for image resource tables and
formats, Browse property binding/validation, read-only Edit flags, native HTTPS
links, plain Text NoPrefix and the exact installed-File launch event. WiX source
was read as an API usage reference; no code/assets/dependency were copied from it.
No advisory scan establishes complete platform or consumer security. Real launch
privilege/identity, navigation and installed servicing remain acceptance checks.

- [Bitmap formats](https://learn.microsoft.com/en-us/windows/win32/msi/bitmap-control)
- [Icon resources](https://learn.microsoft.com/en-us/windows/win32/msi/icon-control)
- [Browse path binding](https://learn.microsoft.com/en-us/windows/win32/msi/pathedit-control)
- [Path validation](https://learn.microsoft.com/en-us/windows/win32/msi/checktargetpath-controlevent)
- [Native hyperlinks](https://learn.microsoft.com/en-us/windows/win32/msi/hyperlink-control)
- [Literal Text controls](https://learn.microsoft.com/en-us/windows/win32/msi/text-control)
- [Native installed-file launch](https://learn.microsoft.com/en-us/windows/win32/msi/msilaunchapp-controlevent)
