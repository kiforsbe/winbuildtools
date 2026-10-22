# Changelog

All notable changes to winbuildtools are listed here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
