# Native MSI preview and acceptance

`verify.ps1` never installs a product. Its table/cabinet and isolated costing
checks cannot establish installed lifecycle, elevation or Windows shell behavior.
Use a disposable Windows installation for the acceptance matrix below. No such
host was available for the 2026-10-23 implementation. The limited, separately
owner-authorized workstation tests on 2026-10-25 are recorded in
[validation](VALIDATION.md#installed-consumer-and-shell-investigation--2026-10-25);
they do not complete the full acceptance matrix or authorize future workstation
changes.

## Native rendering without installation

Build a package normally, then run the inactive Windows Installer preview in STA:

```powershell
pwsh -STA -Command {
  & ./msi/preview.ps1 -Artifact C:/build/app.msi `
    -Dialog @('WbtWelcome','WbtReady','WbtMaintenance','WbtRemove','WbtProgress','WbtExit') `
    -CaptureDirectory C:/build/new-native-preview
}
```

Add `WbtOptions` only with `ui.allowDirectoryChange=true`, `WbtScope` only for choice packages and `WbtLicense` only when license text is
supplied. `-Properties` accepts named strings for display substitutions. The helper
opens the database read-only and uses `EnableUIPreview`/`ViewDialog`; it never
opens an installation session or runs an action. Captures contain only that
process's preview window. Controls are inactive, and conditional visibility/radio
selection can differ from a live session. This proves rendering only, not Back,
keyboard focus, consent, cancellation, progress ticks, UAC or reboot conditions.
The preview is cleared before COM release to avoid native preview shutdown hangs.

Version 0.5.0 presentation support adds `WbtBrowse` (when browsing is enabled) and
`WbtInstallDetails` (when details are enabled). Preview can display both configured
layouts and image resources. Explicit `-Properties @{MsiSystemRebootPending='1';
ReplacedInUseFiles='';UILevel='5'}` selects an ordinary success example even with
an unrelated machine pending restart; this is
display data only, not evidence of reboot or launch behavior. Native inactive
edit/list controls may display no value/content even when the preview property is
set. Validate actual browsing/editing on the disposable host, not from that capture.

## Prepare a synthetic acceptance kit

### Native Finish launch regression without installation

On a Windows desktop, run `pwsh -NoProfile -File msi/tests/test-launch.ps1` explicitly.
It starts a bounded STA subprocess, builds an inert marker executable with the
Windows .NET Framework compiler and opens only the Finish dialog on isolated
packages whose UI/execute sequences were emptied. Native costing resolves the
fixture path, including spaces. Finish must launch the marker when selected,
including authored preselection and an unrelated machine pending restart. The
default unchecked case, a real native click clearing the preselected checkbox,
an explicitly cleared property and transaction restart must not launch it. No installed product, shortcut, trust entry or
real application is changed. This desktop-dependent test is separate from
`verify.ps1` and hosted verification. It does not prove launch privilege behavior
after an elevated install or full installed servicing.

This default command is non-installing and may be run on a development host:

```powershell
./msi/tests/acceptance.ps1 -OutputDirectory C:/build/new-acceptance-kit
```

It authors and inspects two unsigned versions with fresh random ProductCodes,
UpgradeCode, component identities and owned folders, retaining configurations,
MSIs, inspection reports and `acceptance.json`. The local PowerShell executable
is copied as inert PE test bytes for native icons; never launch or redistribute
this payload. Do not transfer these fixture bytes to another machine; generate
the kit there using its installed PowerShell.

Only on a disposable Windows installation, the explicitly opted-in command is:

```powershell
./msi/tests/acceptance.ps1 -OutputDirectory C:/build/new-lifecycle-run `
  -RunLifecycle -DisposableHost -Scope user
```

Repeat for `-Scope machine` from an elevated shell on that disposable host. This
mode installs only its newly generated identities, removes one owned fixture file,
repairs it, upgrades without a destination override to test folder memory, then
uninstalls. It retains verbose per-step logs/results and accepts engine success
or restart-required 3010. Cleanup attempts removal of only those generated
ProductCodes in `finally`. It accepts no arbitrary product identifier or existing
manifest as input. Take a snapshot first and inspect logs/registration/files
afterward; cleanup is not a substitute for isolation.

This silent lifecycle proves neither full-UI event behavior nor Start/UAC/rollback.
It also tests only new-to-new packages; test a real pre-change consumer MSI
separately, passing its known custom `INSTALLFOLDER` where necessary.

## Installed acceptance matrix

Record Windows build, architecture, privilege level, exact MSI hashes, commands,
exit codes, verbose logs and observed results. Use fresh snapshots for each scope
and the actual older release for upgrade compatibility.

| Case | Required observation |
| --- | --- |
| First install, fixed user/machine and choice | Correct default/radio context, destination, native UAC only when needed, registered files and shortcut in the selected context |
| Full wizard | Welcome/options/optional scope/license/Ready flow; Back preserves destination unless scope changes; explicit command-line destination survives; no changes before confirmation |
| License | No page when absent; escaped Unicode/braces render; unchecked/invalid acceptance blocks Next; unattended install needs `WBTACCEPTLICENSE=1` |
| Elevated/managed destination | Selected custom folder survives client/server transfer; compare log properties and actual files under restrictive policy |
| Maintenance and direct `/x` | Same-product launch offers Repair/Remove; direct uninstall asks once; Back/cancel return correctly; no scope editor; repair restores a missing fixture file/shortcut |
| Upgrade | Same scope retained; new-to-new custom directory restored; pre-change custom directory supplied explicitly; earlier version removed transactionally; downgrade blocked |
| Windows 11 Start | App shortcut right-click includes **Uninstall**, invokes visible native removal for its exact ProductCode, and disappears after uninstall; also verify Settings Installed apps and app identity |
| UI levels | `/qf` complete wizard; `/qr` progress with authored Cancel disabled; `/qb` engine-owned interaction; `/qn` no dialogs, correct codes/logs |
| Cancel and rollback | Cancel before changes; cancel during execution; induced failure/rollback; correct result page, cleanup and log; no false completion |
| Running app | Visible/tray, graceful/disabled policy, refusal/non-response; data saved; bounded shutdown, no force kill or relaunch; correct fallback/reboot result |
| Accessibility | Keyboard-only Tab/Shift-Tab/Enter/Escape, accelerators, screen reader, contrast themes, 100/150/200% DPI and text scaling; no clipping at supported settings |
| Completion/reboot | Correct outcome, useful log location, no automatic launch/reboot; return code/log remains authoritative if restart hint is absent |
| Branding/layouts | Both `brandedSidebar` and `compactHeader`; PNG/ICO logo clarity, sidebar aspect ratio, long product names and custom literal messages under DPI/contrast changes |
| Browse/details | Browse Up/typed/existing folders, invalid paths, OK validation, Cancel preserves destination; no pre-confirmation folder creation; Details fields copy full paths/logs |
| Optional launch/links | Unchecked launch stays off; checked launch runs only configured app after install/update, with correct Windows identity/permissions; never launch during repair/removal/transaction restart or unattended UI; unrelated machine pending restart must retain normal success/Run; verify explicit HTTPS help clicks |
| Validation/architecture | Standard ICE validation including ICE105 on user/choice; native x64 and native ARM64 lifecycle, not merely foreign table inspection |

Do not mark a case passed from a screenshot or a table assertion. Shell policy and
caching can affect Start verbs; capture those facts when diagnosing failures.
Package signing/reputation and production trust remain separate consumer checks.

References: [native preview](https://learn.microsoft.com/en-us/windows/win32/msi/previewing-the-user-interface),
[UI levels](https://learn.microsoft.com/en-us/windows/win32/msi/user-interface-levels),
[ICE105](https://learn.microsoft.com/en-us/windows/win32/msi/ice105),
[Start restore/uninstall metadata](https://learn.microsoft.com/en-us/windows/apps/develop/windows-app-restore).
