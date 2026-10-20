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
