# Validation record

2026-10-20, Windows x64. This record concerns local verification; hosted GitHub
execution and actual installer lifecycle acceptance remain separate.

## Checked locally

- Extraction: the engine implementation, schema, example JSON and tests match
  Agenda f1586a4; license/notice/README changes are explicit MIT/standalone updates.
  [provenance.json](provenance.json) records SHA-256 of the extracted implementation.
- MSI: 29 configuration checks and 43 native synthetic checks covering x64/ARM64
  tables, cabinet bytes, stable identities, no custom actions, isolated read-only
  preflight, path normalization and second-product/public-CLI use.
- Common helpers: caller-relative paths, spaces, output/log retention, exit failures,
  missing SDK/tool rejection, no manifest overwrite and final artifact hash.
- MSIX: actual x64/ARM64-manifest MakeAppx packing/unpacking, canonical manifest and exact payload
  comparison, unsigned status, input non-mutation, missing/changed/extra payload,
  reserved metadata, DTD and link/overlapping-output rejection.
- Signing: option conflicts, malformed selectors, password/timestamp rules,
  validity/EKU/private-key/subject checks, missing PFX and unsigned signature
  rejection. Artifact bytes and CurrentUser/My thumbprints remain unchanged.
- .NET: dependency-free managed fixture, explicit locked restore/build/publish
  with matching artifacts context, execution of the published DLL, caller-relative
  logs, missing-lock preflight and failure without an implicit restore when assets
  are absent. The log-path and strict-mode unsigned-manifest regressions were
  observed failing before their fixes and passing afterward.
- Consumer: disposable Git parent with an exact submodule commit, fresh recursive
  clone, missing-checkout guidance and second-product MSI build from another
  directory and paths with spaces. The test permits file transport only on its
  own Git command; it does not change global Git configuration.
- PowerShell syntax, local documentation links, public help, workflow manual-only
  trigger, MIT license consistency and source provenance checks.

Run ./verify.ps1 -Integration to reproduce. The deliberate missing-restore test
prints a NETSDK1004 failure before confirming rejection; this is an expected
negative test, not a suite failure. Other deliberately rejected tool runs also
print their diagnostic tails. Successful verification ends with the pass summary.

## Not established

- Real install/upgrade/repair/uninstall, shortcut repair, ICE validation or
  application-specific notifications/data/coexistence behavior.
- Native ARM64 execution; MSI ARM64 metadata/cabinet inspection is cross-built.
- Live certificate creation, import/trust, PFX/store signing, timestamp service,
  trusted-chain acceptance or production signing infrastructure. Automated tests
  deliberately do not create/trust keys or sign using a user's certificate.
- Store submission/upload packages, bundles, encrypted MSIX or public reputation.
- Hosted workflow execution, remote publication, actual branch/security settings
  or real private cross-repository authentication.
- Every consumer's custom project targets or dependency/license policy. SDK
  artifacts-path support does not prove all application projects use it correctly.
- Independent code review: the dispatched reviewer could not run because the
  account's agent usage limit was reached. This was not a completed review;
  local verification and self-review are recorded separately.

No product, certificate or trust entry is installed by verification. The fixture
managed console executable is run only to confirm the build/publish result.
