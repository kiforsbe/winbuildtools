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
./tests/test-v2.ps1
./tests/test-wizard.ps1
./tests/test-presentation.ps1
```

The output directory must be new and outside the payload. The command returns
Artifact, Version, Architecture, SHA256 and InspectionReport. It creates an
unsigned MSI and a JSON inspection report. Signing belongs to the caller; the
caller must recompute hashes after signing.

## Configuration version 1

See [example.json](example.json) and [config.schema.json](config.schema.json).
The example's top-level fields are required; `ui` is optional in both schemas.
Unknown/duplicate properties are rejected.

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
| application.appUserModelId | Optional existing consumer-owned app identity; 1–128 letters, digits, dots, underscores or hyphens, starting with a letter/digit |
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

## Configuration version 2

Use [example-v2.json](example-v2.json) and [config-v2.schema.json](config-v2.schema.json)
when the consumer must preserve its existing installer identities and folders.
V1 remains supported unchanged. V2 keeps the application/shortcut/payload fields
above and requires these resolved inputs:

| Field | Meaning |
| --- | --- |
| product.productCode | Literal ProductCode for this application release, in braces |
| product.upgradeCode | Literal permanent UpgradeCode; no derivation by shared tools |
| architecture | x64 or ARM64; must match the command argument |
| components | Complete relative payload path to literal component GUID map |
| installation.directoryName | Exact install directory segment; no architecture suffix |
| installation.menuDirectoryName | Independent exact Start-menu directory segment |
| installation.scope | user, machine or choice |
| installation.defaultScope | user or machine; required for choice and forbidden otherwise |
| installation.restartManager | disabled or graceful; explicit in every v2 configuration |

GUIDs must be nonzero and unique across product, upgrade and all components.
Component keys normalize slash styles and compare without case; aliases, missing
and extra mappings are rejected before output is created. Supply one resolved
configuration per architecture. Keep component GUIDs stable for surviving paths
and choose a new ProductCode for a new major-upgrade release. The consumer owns
identity derivation, cross-release compatibility and avoiding shared file ownership
between independently installed products/architectures. Example GUIDs are synthetic;
do not reuse them for an actual product. PackageCode remains fresh per build.

### Installation scope

Choice packages show native **Just me / All users** radio controls in full UI
before FindRelatedProducts and costing. Continue sets ALLUSERS=2 and sets
MSIINSTALLPERUSER=1 for user or clears it for machine. Cancel exits. The chooser
is conditioned on NOT Installed AND UILevel=5: maintenance skips it, and basic,
reduced and silent deployment preserve explicit standard command-line properties.
The full-UI radio selection is authoritative when Continue is pressed.

```powershell
# Explicit unattended user or machine selection for a choice package:
msiexec.exe /i app.msi /qn ALLUSERS=2 MSIINSTALLPERUSER=1 /norestart
msiexec.exe /i app.msi /qn ALLUSERS=2 MSIINSTALLPERUSER="" /norestart
```

Native ProgramFiles64Folder and ProgramMenuFolder follow MSI context redirection;
user installs use the current user's application/program-menu locations, while
machine installs use native Program Files and the shared menu. User/choice packages
have compressed/least-privilege summary WordCount=10; machine packages retain 2.
Fixed user/machine configurations omit the chooser. Installer 5.0 is required.
The authored context is a default, not protection against administrative overrides.

Repairs, removals and upgrades retain the registered context. For an existing
machine installation choose All users (or the explicit machine command above)
when upgrading. Choosing Just me does not migrate/remove the machine registration.
To change scope, uninstall the old installation explicitly first. Do not promise
cross-context related-product discovery or automatic scope migration.

Run ICE105 and normal ICE validation, rendered-dialog, UAC, standard-user,
maintenance and real upgrade/uninstall acceptance on an authorized disposable
Windows host before shipping. Table tests and isolated costing do not prove these.
The v2 tests inspect x64/ARM64 tables and exercise both contexts in native-host
preflight copies; they never install products or elevate.

References: [MSIINSTALLPERUSER](https://learn.microsoft.com/en-us/windows/win32/msi/msiinstallperuser),
[installation context](https://learn.microsoft.com/en-us/windows/win32/msi/installation-context),
[summary flags](https://learn.microsoft.com/en-us/windows/win32/msi/word-count-summary),
[native property events](https://learn.microsoft.com/en-us/windows/win32/msi/setproperty-controlevent).

## V1 identity and common installer behavior

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
and installed products retain MSI maintenance. There is no automatic application launch,
force-termination custom action, certificate trust import, executable custom-action code or user-data
deletion. Uninstall owns only application files and empty app/menu directories.
The engine appends the architecture to installation.directoryName for the app
and menu directories, so separate architecture families cannot overwrite each
other's files. Application-level data and single-instance behavior remain the
consumer's responsibility.

Inspection compares all configured Property, Directory, Component, File/version/hash,
Feature, Upgrade/range/action-property, LaunchCondition, search, shortcut, media,
folder-ownership and action-sequence rows plus summary metadata and scope/UI
policy before native preflight or extraction. It then compares extracted cabinet bytes. Read-only native search/costing preflight runs only
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

## Native setup and maintenance

Newly authored MSIs use a native Windows Installer wizard with consistent Segoe UI
typography, headers, publisher/footer and Back/Next/Cancel controls:

```mermaid
flowchart LR
    Welcome --> Scope[Scope if choice]
    Scope --> Options[Destination if editable]
    Options --> License[License if supplied]
    License --> Ready
    Ready --> Prepare[Show modeless progress]
    Prepare --> Cost[Native discovery and costing]
    Cost --> Upgrade[Upgrade confirmation if needed]
    Upgrade --> Progress[Continue engine progress]
    Progress --> Result[Completed / canceled / failed]
```

Absent optional pages are skipped. Choices and Back navigation finish before
related-product discovery/costing. A same-product launch offers Repair/Remove;
`msiexec /x {ProductCode}` opens removal confirmation directly. Maintenance never
offers a scope change. Repair/removal use native feature-state events. Windows
Installer owns progress ticks, rollback and files-in-use handling. Welcome uses
neutral instructions; the engine requests application closure only when files
are in use. A single modeless progress page opens after Install consent, before
discovery/costing. Post-cost maintenance/upgrade/error confirmations retain it
with the native KeepModeless flag; termination pages replace it. Full UI asks
before cancellation. Reduced `/qr` shows progress with Cancel disabled because
MSI's authored cancellation events require full UI; use `/qb` for the engine's
built-in interactive progress/cancellation or `/qf` for the wizard. `/qn` has no UI.
Installed behavior still requires the [acceptance checks](../docs/MSI-ACCEPTANCE.md).

Both schemas accept these optional presentation fields:

```json
"ui": {
  "layout": "brandedSidebar",
  "logo": "Assets/logo.png",
  "sidebarImage": "Assets/setup-sidebar.png",
  "allowDirectoryChange": true,
  "showBrowseButton": true,
  "completion": {
    "launchApplication": true,
    "showDetails": true,
    "releaseNotesUrl": "https://example.com/releases",
    "helpUrl": "https://example.com/getting-started",
    "messages": {
      "installed": "The application is ready to use.",
      "updated": "The new version is ready.",
      "repaired": "Application files have been restored.",
      "removed": "The application has been removed.",
      "canceled": "Setup was canceled. Review the log if needed.",
      "failed": "Setup failed. Review the log before retrying.",
      "restartRequired": "Restart Windows to finish applying changes."
    }
  }
}
```

See [example-ui.json](example-ui.json) for a complete v2 configuration. The same
`ui` object is accepted by v1. Omit options to retain defaults; unknown fields,
contradictory options, unsafe paths/URLs and invalid images are rejected.

| Field | Contract and default |
| --- | --- |
| `ui.layout` | `compactHeader` (default) or `brandedSidebar`; sidebar applies to welcome/result pages, with compact headers on intermediate pages |
| `ui.logo` | Optional payload-relative ICO/PNG/JPEG/BMP; small header logo and larger sidebar logo when no full sidebar image is supplied |
| `ui.sidebarImage` | Optional PNG/JPEG/BMP artwork; requires explicit `brandedSidebar`; includes its own logo/lettering and fills the sidebar without text overlays |
| `ui.showBrowseButton` | Defaults to true when directory editing is enabled; explicit true requires `allowDirectoryChange=true`; false retains direct text editing |
| `ui.completion.launchApplication` | Default false; offers an initially unchecked Run checkbox after successful full-UI install/update |
| `ui.completion.showDetails` | Default true; adds a modal Details button with selectable folder/log fields, version, architecture and context |
| `ui.completion.releaseNotesUrl` / `helpUrl` | Optional literal HTTPS URLs, at most 1024 characters; no credentials, MSI property references or shell/file protocols |
| `ui.completion.messages` | Optional plain-text body overrides for `installed`, `updated`, `repaired`, `removed`, `canceled`, `failed`, `restartRequired`; 1–160 printable characters each; headings remain tied to the actual operation |

Images must already be approved payload files and are implicitly required when
referenced. They are also installed as ordinary payload components, so v2 component
maps must include them. Each image is limited to 8 MiB and 2048×2048 pixels, decoded
before output creation; its actual format must match its extension. Use artwork
with the intended aspect ratio: roughly 1:1 for logos and 120:242 for sidebar art.
Images are embedded in the MSI's native Binary table; exact resource names and
SHA-256 bytes are checked before any costing. For ICO logos the UI resource moves
the largest-area frame (highest bit depth on a tie) to the first directory entry,
which native MSI loads. All encoded frames and the installed payload ICO remain
unchanged. The selected frame is decoded before authoring; inspection recomputes
the exact derived resource hash. Other image formats remain byte-identical to
their payload source. No download or image package is used.

Finish pages distinguish installation, update, repair and removal. Normal logs
sit behind Details; cancellation/failure retain visible log information even when
`showDetails=false`. Restart text appears only when the transaction sets
`ReplacedInUseFiles` during execution/finalization, with a clear instruction to
restart. An unrelated machine `MsiSystemRebootPending` flag does not override
successful completion or hide Run. This engine authors file/shortcut/registration
operations only: no services, drivers, prerequisites, reboot actions or executable
custom actions. General `MSIRUNMODE_REBOOTATEND` is a session API mode, not an MSI
condition property; the wizard does not claim to read that mode. Deployment must
still preserve Windows Installer's actual result, including 3010 when returned.
Hyperlinks appear after successful install/update. Their destinations belong to
the consumer and open in the default browser only when clicked.

See Microsoft's [transaction file-replacement signal](https://learn.microsoft.com/en-us/windows/win32/msi/replacedinusefiles),
[machine pending flag](https://learn.microsoft.com/en-us/windows/win32/msi/msisystemrebootpending),
[native ICO selection](https://learn.microsoft.com/en-us/windows/win32/msi/icon-control)
and [KeepModeless behavior](https://learn.microsoft.com/en-us/windows/win32/msi/keepmodeless-dialog-style-bit).

The Run checkbox never defaults to checked and is absent during repair, removal,
failure/cancellation, reduced/basic/silent UI or transaction in-use replacement. Its
native `MsiLaunchApp` event accepts only the configured executable's installed File
key, with no command/argument fields. Actual launch identity/privilege behavior
still needs disposable-host acceptance, especially when setup was started elevated.
No launch or URL is followed during packaging, inspection, preview or verification.

Browse uses native PathEdit/DirectoryList controls and a temporary path property.
OK validates before committing; Cancel preserves the original destination. It
offers no New folder action that could write directories before confirmation.
Native costing remains responsible for the final destination validation.

Destination editing defaults to false. When disabled, the Options page is omitted
and Ready shows the fixed destination once before the Install button. Optional
scope/license pages and Back navigation follow the remaining chain. Enabling
editing retains Options, with Browse separately configurable. There is no schema
field for choosing/editing the log path: Details shows it read-only,
and deployment may choose its logging destination through `msiexec /L*v`.
A command-line `INSTALLFOLDER` is honored in full UI; Back preserves edits until
scope is actually switched. The resolved
`INSTALLFOLDER` and `WBTACCEPTLICENSE` are secured for UI-to-server transfer under
elevated managed installation. License text is plain text (1–4096 characters),
escaped into Unicode RTF; omit it if no agreement is required. Supplied licenses
require explicit checkbox acceptance in full UI or `WBTACCEPTLICENSE=1` for
unattended/basic/reduced installation. Repair/removal skip this new-install gate.

Windows application registration includes `ARPINSTALLLOCATION` and an icon (the
configured icon, otherwise the executable). Each Start shortcut gets native
`System.AppUserModel.UninstallCommand` metadata targeting visible `msiexec /x`
for that ProductCode. An optional `application.appUserModelId` is copied exactly;
use the application's existing identity. No extra Uninstall shortcut is created.
Actual Windows 11 Start right-click **Uninstall** remains an installed acceptance
check; shell caching/policy can affect its presentation.

New packages remember the resolved destination in the native context's
`Software\winbuildtools\Installations\{UpgradeCode}` registry key, value
`InstallLocation`, owned by the executable component. AppSearch restores it before
costing for same-context maintenance/upgrades. Three exact declarative type-51
setters support this and ARP location; no executable/script custom actions are
allowed. Inspection compares their exact names, types, properties and values,
alongside the single registry row and shortcut properties. `CustomActionCount`
therefore reports 3 and `RegistryCount` reports 1.

**Older-package boundary:** MSIs authored before this change have no folder-memory
record. When upgrading an older custom-folder installation, explicitly supply its
known `INSTALLFOLDER`; it cannot be recovered by this mechanism. Choose the old
scope too. Cached older packages retain their own UI/removal policy. A consumer
must rebuild with a deliberately updated tool pin; this does not update installed
Agenda/ProcSight packages by itself.

Automatic native logging is enabled with `MsiLogging=voicewarmupx`; result pages
show `MsiLogFileLocation` when available. `/L*v path.log` gives deployments a
known retained log. Transaction file-replacement restart text complements engine exit codes
(including 3010) and logs even when reboot prompts are suppressed. Optional launch
requires the consumer setting and user checkbox above. [Preview and acceptance](../docs/MSI-ACCEPTANCE.md) distinguishes
inactive native rendering from actual servicing acceptance.

References: [shortcut properties](https://learn.microsoft.com/en-us/windows/win32/msi/msishortcutproperty-table),
[ARP location](https://learn.microsoft.com/en-us/windows/win32/msi/arpinstalllocation),
[secure transfer](https://learn.microsoft.com/en-us/windows/win32/msi/securecustomproperties),
[full-UI EndDialog](https://learn.microsoft.com/en-us/windows/win32/msi/enddialog-controlevent).

## Running applications

V2 disabled packages instead use `MSIRESTARTMANAGERCONTROL=Disable`: users must
close the application themselves; legacy files-in-use UI remains available. This
is consumer policy, not an inferred choice based on the product name.

V1 and v2 graceful packages use `MSIRESTARTMANAGERCONTROL=0` to enable Windows Installer's
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
| Configuration.ps1 / config*.schema.json | Duplicate-key rejection, strict JSON fields and semantic path checks |
| Identity.ps1 | Product/architecture namespaces and stable UUIDs |
| Payload.ps1 | Link rejection, approved paths, bounded payload enumeration |
| Database.ps1 | Native COM lifetime, parameterized SQL records and tool execution |
| Maintenance.ps1 | Reserved files-in-use dialogs, consent/cancel events and maintenance policy inspection |
| Scope.ps1 | Native scope properties, chooser authoring and exact scope UI inspection |
| Registration.ps1 | Bounded shortcut/ARP registration, context-owned folder memory and three exact type-51 setters |
| Branding.ps1 | Approved image validation, native Binary streams and exact resource-byte inspection |
| Presentation.ps1 | Both layouts, Browse/Details pages, operation-specific results and bounded native launch/links |
| Wizard.ps1 | Declarative setup/servicing/progress/result pages and exact native UI inspection |
| preview.ps1 | Read-only inactive native dialog preview/capture; requires `pwsh -STA` |
| Semantics.ps1 | Complete expected table/summary comparisons before preflight/extraction |
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
Run all five test scripts in the destination and exercise a second product config
using relative paths from a different directory. Keep publishing, signing, license
review and dependency acquisition in consumer adapters. Do not add imports back
into Agenda or application-specific filenames. A future shared release should be
pinned by its consumers and retain this source license/provenance.
