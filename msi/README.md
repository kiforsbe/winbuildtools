# Native MSI tooling

This directory is self-contained. Copy it to another repository or run it from
any working directory. Windows and PowerShell 7.4 or later are required; Windows supplies
Windows Installer Automation, MakeCab and Expand. No .NET SDK, WinUI, WiX,
third-party PowerShell module or repository checkout is needed by the engine.

```powershell
./package.ps1 -Config ./example.json -PayloadDirectory C:/build/payload `
  -Version 1.2.3 -Architecture x64 -OutputDirectory C:/build/new-installer
./tests/test-config.ps1
./tests/test-msi.ps1
```

The output directory must be new and outside the payload. The command returns
Artifact, Version, Architecture, SHA256 and InspectionReport. It creates an
unsigned MSI and a JSON inspection report. Signing belongs to the caller; the
caller must recompute hashes after signing.

## Configuration version 1

See [example.json](example.json) and [config.schema.json](config.schema.json).
All top-level fields are required. Unknown/duplicate properties are rejected.

| Field | Meaning |
| --- | --- |
| schemaVersion | Integer 1 |
| product.id | Stable identifier used for artifact filenames |
| product.name / manufacturer | Product display name and publisher |
| product.upgradeCode | Permanent product namespace GUID in braces |
| installation.scope | machine |
| installation.directoryName | One owned directory under native Program Files |
| installation.minimumWindowsBuild | Numeric Windows build, at least 22000 |
| application.executable | Payload-relative .exe, including any subdirectory |
| application.icon | Optional payload-relative icon |
| shortcuts | One to ten unique names with location startMenu |
| payload.requiredFiles | Files that must exist in addition to executable/icon |
| payload.allowedExtensions | Approved extensions including the leading dot |
| payload.allowedFiles | Additional exact approved relative paths |

Paths are relative to the payload, independent of the config file's location.
No traversal, rooted paths, alternate streams, wildcard patterns, device names,
trailing dots/spaces, links or reparse points are supported. Approve only the
formats your published application needs. This tool does not classify whether
a permitted file contains secrets. Product configuration owns that policy.

Version is three components, maximum 255.255.65534. Architectures are x64 and
ARM64. The cabinet is limited to 10,000 files and 2 GiB uncompressed content;
a single file must fit a signed 32-bit MSI FileSize. Cabinet directive characters
and short-name collisions are rejected. Use a new output directory on retry.

## Identity and installer behavior

Keep product.upgradeCode and installation.directoryName stable after a release.
Use a different upgradeCode for every independently installed product; do not
reuse example.json's namespace. Component identities depend on that namespace,
architecture and normalized relative path. The engine derives separate x64 and
ARM64 upgrade families; changing architecture does not replace the other family.
Product codes depend on version and package codes are fresh for every authoring.
Do not change a shipped version's contents and expect it to act as an upgrade.

The installer uses native Program Files, an advertised Start-menu shortcut and
standard Windows Installer actions. Restart Manager requests normal shutdown of
applications using affected files; see [Running applications](#running-applications).
Older MSI versions are removed transactionally, same/newer versions are detected,
and installed products retain MSI maintenance. There is no application launch,
force-termination custom action, certificate trust import, custom-action code or user-data
deletion. Uninstall owns only application files and empty app/menu directories.
The engine appends the architecture to installation.directoryName for the app
and menu directories, so separate architecture families cannot overwrite each
other's files. Application-level data and single-instance behavior remain the
consumer's responsibility.

Inspection verifies database identity, file/component mappings, owned folders
and extracted cabinet bytes. Read-only native search/costing preflight runs only
for the host's native architecture, against a copy with new product/upgrade/
package/component identities, disposable target paths and Restart Manager disabled.
The original package's maintenance policy/UI is checked separately. Preflight never initializes
or executes an installation transaction. Cross-architecture inspection checks
tables and bytes but does not launch the foreign installer engine.

Synthetic inspection does not prove actual installation, upgrade, repair,
uninstall, shortcut repair or notification behavior. Perform lifecycle testing
on disposable compatible Windows hosts and run ICE validation before shipping.
Unsigned MSI requires no development certificate import; Windows policy and
reputation can still warn or block it.

The engine does not verify dependency advisories, license compatibility or
application behavior. The consuming repository owns those checks. See
[NOTICE.md](NOTICE.md) and [LICENSE](LICENSE) for provenance and source terms.

## Running applications

The authored package uses `MSIRESTARTMANAGERCONTROL=0` to enable Windows Installer's
Restart Manager integration, `MSIRMSHUTDOWN=0` for normal shutdown rather than the
force-shutdown option, and `MSIDISABLERMRESTART=1` to suppress automatic relaunch
after uninstall, repair and upgrade. `REBOOT=ReallySuppress` continues to suppress
automatic reboot and reboot prompts. This is an installer policy, not a guarantee
that every application will exit or that no reboot will be needed. Machine policy
or unavailable Restart Manager support can override the integration.

| UI level | Files-in-use behavior |
| --- | --- |
| Full (`/qf`) | Native `MsiRMFilesInUse` dialog lists applications. After saving work, the user can explicitly choose **Close applications** or **Cancel**. Enter/Escape defaults to Cancel. If Restart Manager is unavailable, `FilesInUse` offers manual close + Retry, Continue without closing (possibly requiring a reboot), or Cancel. Authored error and completion/cancellation/failure dialogs report the outcome. |
| Reduced (`/qr`) | Windows Installer provides RM interaction; the full-only RM dialog is not used. Authored error and legacy FilesInUse dialogs remain available. Follow the prompt or close the application manually. |
| Basic (`/qb`) | Windows Installer supplies built-in files-in-use/Restart Manager/error/progress interaction, without authored dialogs. Follow the native prompt or close the application manually. |
| Silent (`/qn`) | No consent dialog is displayed. Deployment can request normal application shutdown without prompting. An uncooperative app or policy restriction can cause failure or a reboot requirement; unattended deployment must account for this behavior. |

The full-UI Close button publishes the documented `RMShutdownAndRestart` event;
the no-relaunch property still applies. Cancel exits setup; the fallback Retry
rechecks after manual closure. The legacy Ignore result is explicitly labelled
Continue without closing and can defer changes until reboot. There is no force-kill path, no
process-name matching, no `taskkill`, and no direct `RmShutdown` custom action.
Do not override the policy properties to force termination or enable relaunch as
part of routine consumer packaging. Inspection rejects unexpected property values,
missing dialogs, invalid list bindings and broken consent/retry/cancel wiring.
The standard error dialog includes all seven native error-result buttons; Windows
chooses the subset appropriate to the message. Success, cancellation and failure
have separate termination dialogs. Their presence is checked structurally, not by
claiming an ICE run. These are authored defaults, not protection against an
administrator changing MSI properties, applying transforms or system policy.

Applications must cooperate with Windows. For GUI applications, acknowledge
`WM_QUERYENDSESSION` promptly when ready, without exiting solely on the query.
On committed `WM_ENDSESSION` (`wParam=TRUE`), save needed state, release resources
and exit the process within the Windows shutdown deadline. A canceled end-session
notification must not exit the app. A close-to-tray implementation must not hide
the process instead of ending it after committed shutdown. Handle duplicate HWND
notifications idempotently and avoid cross-thread shutdown waits that deadlock.
Enabling Restart Manager does not implement this application behavior for consumers.

This change affects newly authored MSIs. It does not rewrite old built packages
or cached installed MSI databases; an old package's removal during an upgrade may
still use its previous policy. Use a new application release version and validate
the upgrade from the actual older MSI, not just between newly authored fixtures.

Before release, explicitly authorize lifecycle acceptance in a disposable Windows
environment: test uninstall, repair and major upgrade with the application visible
and in the tray, full/basic/reduced/silent UI, user cancellation, shutdown refusal
or non-response, and machine-policy fallback. Confirm data/state persistence,
bounded shutdown without forced termination, no automatic relaunch (including
apps registered for restart), correct exit codes and no unintended reboot. Capture
verbose logs and check for reboot-required results such as 3010; suppressed reboot
prompts do not mean all files were removed immediately. Run ICE validation on the
authored UI tables. These acceptance checks are not performed by `verify.ps1`.

The reported Agenda uninstall delay remains unproven: the available verbose log
records only a successful retry after the app was closed. Synthetic table tests
are not evidence that a prior running-app stall is fixed.

Authoritative references:

- [Using Windows Installer with Restart Manager](https://learn.microsoft.com/en-us/windows/win32/msi/using-windows-installer-with-restart-manager)
- [Restart Manager control](https://learn.microsoft.com/en-us/windows/win32/msi/msirestartmanagercontrol), [shutdown](https://learn.microsoft.com/en-us/windows/win32/msi/msirmshutdown) and [restart suppression](https://learn.microsoft.com/en-us/windows/win32/msi/msidisablermrestart)
- [MsiRMFilesInUse](https://learn.microsoft.com/en-us/windows/win32/msi/msirmfilesinuse-dialog), [RMShutdownAndRestart](https://learn.microsoft.com/en-us/windows/win32/msi/rmshutdownandrestart-controlevent) and [FilesInUse](https://learn.microsoft.com/en-us/windows/win32/msi/filesinuse-dialog)
- [Application shutdown guidelines](https://learn.microsoft.com/en-us/windows/win32/rstmgr/guidelines-for-applications)
- [UI levels](https://learn.microsoft.com/en-us/windows/win32/msi/user-interface-levels), [standard dialog requirements](https://learn.microsoft.com/en-us/windows/win32/msi/ice20) and [error dialog](https://learn.microsoft.com/en-us/windows/win32/msi/error-dialog)

## Maintenance and standalone use

See [Running applications](#running-applications) before changing maintenance policy.

| File | Responsibility |
| --- | --- |
| package.ps1 | Public command, filesystem-provider path resolution, output/result contract |
| Configuration.ps1 / config.schema.json | Duplicate-key rejection, strict JSON fields and semantic path checks |
| Identity.ps1 | Product/architecture namespaces and stable UUIDs |
| Payload.ps1 | Link rejection, approved paths, bounded payload enumeration |
| Database.ps1 | Native COM lifetime, parameterized SQL records and tool execution |
| Maintenance.ps1 | Reserved files-in-use dialogs, consent/cancel events and maintenance policy inspection |
| Authoring.ps1 | Cabinet directives, standard tables, short/long aliases and action sequencing |
| Inspection.ps1 | Database mappings, embedded-byte comparison and isolated read-only preflight |
| tests/ | Synthetic config/native fixtures and extraction regression |

The 7.4 floor provides supported PowerShell/.NET APIs for SHA-256 helpers and
the JSON validator; Windows PowerShell 5.1 and early unsupported 7.x releases
are rejected before script execution. No runtime installation is performed.

Native table/action choices are deliberately explicit. Keep RemoveExistingProducts
inside the InstallInitialize/InstallFinalize transaction; preserve all ordinary
unpublish/removal actions required by uninstall. Signature must exist even for a
raw registry AppSearch. Versioned PE files use their fixed binary version; other
files use MsiFileHash records. Root directories and shortcuts use deterministic
8.3|long aliases, as do payload files/subdirectories. Never substitute display
file-version text or introduce executable custom actions as a convenience.

Relative command paths follow the current PowerShell filesystem location, including
after Set-Location. Payload approval and component identities normalize both slash
styles. Paths in JSON remain relative to the payload, not relative to the config.

When copying, include this entire directory including LICENSE/NOTICE and tests.
Run both test scripts in the destination and exercise a second product config
using relative paths from a different directory. Keep publishing, signing, license
review and dependency acquisition in consumer adapters. Do not add imports back
into Agenda or application-specific filenames. A future shared release should be
pinned by its consumers and retain this source license/provenance.
