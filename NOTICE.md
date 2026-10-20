# Provenance

The msi/ directory was extracted unchanged from Agenda tools/msi/ at commit
f1586a4 on 2026-10-20: https://github.com/kiforsbe/agenda.
Its native MSI implementation was adapted from ProcSight revision 17cf576:
https://github.com/kiforsbe/procsight. Preserve msi/NOTICE.md and its license.

MSIX, signing, SDK discovery and tool logging are generalized adaptations of
Agenda's packaging helpers at the same revision. New build, integration and
verification helpers were added for winbuildtools. The source is distributed
under GNU AGPL version 3, supplied in LICENSE. No private keys, application
payloads, Windows SDK binaries or .NET runtimes are distributed here.

Windows, Git, PowerShell, the Windows SDK and optional .NET SDK retain their own
license and support terms. This repository does not grant application payload
redistribution rights. Consumers own their dependencies and license decisions.
