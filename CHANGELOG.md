# Changelog

All notable changes to winbuildtools are listed here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
