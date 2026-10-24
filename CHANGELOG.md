# Changelog

All notable changes to winbuildtools are listed here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- MSI wizard text uses concise, conventional installation wording throughout,
  including completion, cancellation and the optional Launch checkbox.
- Fixed-folder MSI installs skip the redundant Options page; progress appears
  before discovery/costing and stays available across maintenance confirmations.
- MSI completion ignores unrelated machine pending restarts, retains opt-in Run
  after successful install/update, and reports transaction file-replacement restarts.
- Wizard ICO logos select the largest frame instead of stretching the first small
  frame; inspection verifies the derived resource ([UI contract](msi/README.md#native-setup-and-maintenance)).
- Welcome no longer asks users to close an application that may not be running;
  native files-in-use detection requests closure only when needed.

## [0.5.0-beta.1] - 2026-10-24

### Added

- Both MSI schemas accept branded-sidebar/compact-header layouts, logo/artwork,
  native folder browsing and configurable completion options ([UI contract](msi/README.md#native-setup-and-maintenance)).
- Completion pages distinguish install/update/repair/removal and support optional
  app launch, HTTPS help links and installation details through `ui.completion`.

### Known limitations

- Installed Browse/link/launch behavior, launch privileges, UAC, ICE and accessibility
  still require disposable-host acceptance ([acceptance guide](docs/MSI-ACCEPTANCE.md)).
- Disabling folder changes leaves its Options page visible; log paths are read-only
  and deployment-controlled rather than editable through the schema.

## [0.4.0] - 2026-10-23

### Added

- Opt-in MSI v2 accepts literal identities/folders, explicit servicing policy and
  native Just me / All users scope choice ([v2 contract](msi/README.md#configuration-version-2)).
- Store-free bounded public certificate validation and object-based trust import
  helpers support consumer UAC wrappers ([integration](docs/INTEGRATION.md#public-certificate-validation-before-elevation)).
- Native MSI setup/repair/remove wizard, engine progress and result/log pages,
  with optional destination editing and license text ([MSI guide](msi/README.md#native-setup-and-maintenance)).
- Non-installing native dialog preview and a separately opted-in disposable-host
  lifecycle kit ([acceptance guide](docs/MSI-ACCEPTANCE.md)).

### Changed

- New MSIs register Start-shortcut uninstall metadata, ARP location/icon and
  same-context custom-folder memory for subsequent upgrades ([MSI guide](msi/README.md#native-setup-and-maintenance)).

### Fixed

- MSI inspection rejects altered destinations, upgrade rules, file versions/hashes,
  scope and configured metadata before native costing or payload extraction.

### Security

- Development trust imports the validated in-memory certificate instead of reopening
  its path, preventing certificate substitution after validation.

### Known limitations

- V2 scope UI, ICE105, UAC and installed lifecycle acceptance remain manual;
  changing scope requires explicit removal of the previous installation.
- Start right-click Uninstall and installed wizard/servicing acceptance remain
  pending; older custom-folder packages need an explicit destination on upgrade.
- Reduced MSI UI shows progress with authored Cancel disabled; use full or basic
  UI for interactive cancellation ([UI behavior](msi/README.md#native-setup-and-maintenance)).

## [0.4.0-beta.1] - 2026-10-23

### Added

- Opt-in MSI v2 accepts literal identities/folders, explicit servicing policy and
  native Just me / All users scope choice ([v2 contract](msi/README.md#configuration-version-2)).
- Store-free bounded public certificate validation and object-based trust import
  helpers support consumer UAC wrappers ([integration](docs/INTEGRATION.md#public-certificate-validation-before-elevation)).
- Native MSI setup/repair/remove wizard, engine progress and result/log pages,
  with optional destination editing and license text ([MSI guide](msi/README.md#native-setup-and-maintenance)).
- Non-installing native dialog preview and a separately opted-in disposable-host
  lifecycle kit ([acceptance guide](docs/MSI-ACCEPTANCE.md)).

### Changed

- New MSIs register Start-shortcut uninstall metadata, ARP location/icon and
  same-context custom-folder memory for subsequent upgrades ([MSI guide](msi/README.md#native-setup-and-maintenance)).

### Fixed

- MSI inspection rejects altered destinations, upgrade rules, file versions/hashes,
  scope and configured metadata before native costing or payload extraction.

### Security

- Development trust imports the validated in-memory certificate instead of reopening
  its path, preventing certificate substitution after validation.

### Known limitations

- V2 scope UI, ICE105, UAC and installed lifecycle acceptance remain manual;
  changing scope requires explicit removal of the previous installation.
- Start right-click Uninstall and installed wizard/servicing acceptance remain
  pending; older custom-folder packages need an explicit destination on upgrade.
- Reduced MSI UI shows progress with authored Cancel disabled; use full or basic
  UI for interactive cancellation ([UI behavior](msi/README.md#native-setup-and-maintenance)).

## [0.3.0] - 2026-10-22

### Changed

- MSI maintenance can request graceful application shutdown through Windows
  Restart Manager, with interactive files-in-use dialogs and no automatic relaunch
  ([UI policy and application requirements](msi/README.md#running-applications)).

### Known limitations

- Running-app uninstall/repair/upgrade, rendered dialogs and ICE validation still
  require acceptance testing on an approved disposable Windows host.
- Previously built or cached installed MSIs retain their original maintenance policy.

## [0.2.0] - 2026-10-22

### Changed

- Consumer integration now covers all shared packaging, signing, certificate,
  SDK/logging and final metadata mechanisms, including additive product fields
  ([migration guide](docs/INTEGRATION.md)).
- Publishing and tagging use local verification; GitHub Actions runs only when
  explicitly requested ([publication guidance](docs/GITHUB.md)).

### Security

- Private vulnerability reporting is available on GitHub
  ([reporting guidance](SECURITY.md)).

## [0.1.0] - 2026-10-22

### Added

- JSON-configured native MSI packaging for x64 and ARM64, extracted from Agenda
  ([MSI guide](msi/README.md)).
- MSIX packing and inspection, explicit signing and verification, separate
  development certificate tools, SDK discovery, logs and final hash manifests.
- Locked .NET restore and isolated build/publish commands
  ([.NET operations](README.md#net-operations)).
- Pinned-checkout integration guidance and manual-only GitHub verification
  ([integration](docs/INTEGRATION.md), [validation](docs/VALIDATION.md)).
- MIT licensing with copyright-holder authorization and preserved Agenda/ProcSight
  attribution ([license](LICENSE), [provenance](NOTICE.md)).

### Fixed

- `Get-Help -Full` now displays the command descriptions and parameter guidance
  for commands whose help blocks were not recognized after `#requires`.
