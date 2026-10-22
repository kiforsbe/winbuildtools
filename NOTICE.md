# Provenance

The msi/ implementation was extracted unchanged from Agenda tools/msi/ at commit
f1586a4 on 2026-10-20: https://github.com/kiforsbe/agenda.
Its native MSI implementation was adapted from ProcSight revision 17cf576:
https://github.com/kiforsbe/procsight. Preserve this attribution and msi/NOTICE.md.

On 2026-10-21, maintenance comments were added to the extracted scripts without
changing executable tokens. docs/provenance.json retains the extraction hashes
alongside current hashes and records these local modifications.

On 2026-10-22, MSI authoring, inspection, the public loader and standalone tests
were extended for native Windows Installer Restart Manager policy and files-in-use
UI. msi/Maintenance.ps1 is new winbuildtools code. The extraction hashes are retained;
current hashes and the local functional modifications are recorded separately.

MSIX, signing, SDK discovery and tool logging are generalized adaptations of
Agenda's packaging helpers at the same revision. New build, integration and
verification helpers were added for winbuildtools. The source is distributed
under the MIT License, supplied in LICENSE. The copyright holder confirmed on
2026-10-20 that they have the rights to relicense all copied Agenda/ProcSight
code and explicitly requested MIT for this repository. The previous AGPL
license documents and references were replaced here under that authorization;
the original repositories retain their own licensing. The MIT text comes from
https://github.com/github/choosealicense.com/blob/gh-pages/_licenses/mit.txt.
No private keys, application
payloads, Windows SDK binaries or .NET runtimes are distributed here.

Windows, Git, PowerShell, the Windows SDK and optional .NET SDK retain their own
license and support terms. This repository does not grant application payload
redistribution rights. Consumers own their dependencies and license decisions.
