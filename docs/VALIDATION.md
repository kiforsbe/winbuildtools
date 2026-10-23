# Validation record

2026-10-20, Windows x64. This record concerns local verification; hosted GitHub
execution and actual installer lifecycle acceptance remain separate.

## Checked locally

- Extraction: at extraction, the engine implementation, schema, example JSON and
  tests matched Agenda f1586a4; license/notice/README changes were explicit
  MIT/standalone updates. [provenance.json](provenance.json) records current hashes
  and retains original extraction hashes for subsequently modified scripts.
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

## Maintenance documentation verification — 2026-10-21

The architecture guide and maintenance comments were checked against the code.
An independent reviewer found no substantive issues; its wording suggestion was
applied. The earlier extraction review limitation above remains a historical record.

- `./verify.ps1 -Integration` passed on Windows x64 10.0.26300.0 with PowerShell
  7.6.5, Windows SDK tools 10.0.26100.0 and .NET SDK 10.0.301. Coverage and exclusions
  remain those described above. The pinned consumer cloned committed revision
  `0f623a61f46e6ef24fe4ae626244fb3bb8e5628d`; other tests used the working tree.
- PowerShell parser comparisons against HEAD confirmed identical executable
  tokens for all 31 scripts and the workflow's embedded checkout script, excluding
  comments/newlines. All scripts parsed without errors. This checks executable
  text, not help output: comment help was deliberately expanded and separated
  from `#requires` so PowerShell recognizes it.
- All 11 public/example commands exposed a parsed synopsis and description through
  `Get-Help -Full`. Repository checks passed for current provenance hashes and local
  documentation targets. `git diff --check` passed.
- Original extraction hashes remain in `ExtractionSHA256` for the nine locally
  commented MSI scripts; `SHA256` records their current bytes. Schema/example
  inputs are unchanged. No dependency was added or upgraded.

This documentation change does not establish any of the installer lifecycle,
native ARM64, live signing/trust or hosted-CI acceptance excluded above.

## Consumer integration release 0.2.0 — 2026-10-22

This release expands integration guidance and the MSI-only example's help; it
does not change shared command parameters, results, executable logic, dependencies
or the generic artifact metadata schema.

- `./verify.ps1 -Integration` passed locally on Windows x64 10.0.26300.0,
  PowerShell 7.6.5, Windows SDK 10.0.26100.0 and .NET SDK 10.0.301. This included
  29 configuration checks, 43 native MSI checks, MSIX roundtrips/rejections,
  signing validation, .NET build/publish and pinned recursive consumer packaging.
  Before the release commit, the pinned clone exercised committed `48b72d2`;
  the other tests exercised the release working tree.
- All eight PowerShell blocks in the integration guide parsed without errors.
  A parser-token comparison confirmed the example adapter's executable tokens
  were unchanged from the previous commit. `git diff --check` passed.
- Independent review found the examples consistent with shared helper contracts,
  including preserved generic hash/signature fields, additive Format/Architecture
  and Commit fields, separate certificate/trust commands and explicit trust policy.
- An ad-hoc end-to-end metadata-composition fixture command was rejected by
  automatic approval review as "blocked by policy" before execution. The example
  was reviewed and parsed, but that extra execution check was not completed.
  Existing common-helper tests cover the generic writer, not consumer composition.
- No GitHub workflow or hosted release was requested or started for this release.
  No live signing, certificate creation/import, installed lifecycle acceptance or
  Agenda migration is established by these winbuildtools checks.

## Restart Manager release 0.3.0 — 2026-10-22

Local non-installing verification passed on Windows x64 10.0.26300.0, PowerShell
7.6.5, Windows SDK 10.0.26100.0 and .NET SDK 10.0.301:

- `./msi/tests/test-msi.ps1`: 157 checks, including x64/ARM64 maintenance properties,
  native files-in-use/error/termination UI tables, safe default/cancel mappings,
  legacy Retry/Ignore behavior, seven error-result buttons and termination entries.
- Twenty-three copied-MSI mutation cases rejected unsafe shutdown/restart/reboot
  policy, suppressed full UI, missing/malformed consent/error/result mappings,
  process-list binding, disabled controls and unusable control rectangles. Rejected
  inputs retained their hashes and did not produce payload extraction evidence.
- Read-only preflight disables Restart Manager in its isolated database before
  OpenPackage, including when the source omitted the property. The original MSI
  retains the production policy and unchanged bytes. No shutdown or installation
  transaction is part of verification.
- Red/green observations covered the previously disabled RM property, missing
  UI tables, a forced-shutdown MSI accepted without inspection enforcement, missing
  native error support, an accepted zero-width error control, and a preflight copy
  that failed to insert a missing disabling property. Each was observed failing
  before the corresponding implementation/enforcement change and passing afterward.
- `./verify.ps1 -Integration` passed, including common/MSIX/signing/.NET/repository
  checks and standalone engine use. Its pinned recursive consumer cloned committed
  `99d60cf6f0ef4b823f55237e664fc02684bb001d` (v0.2.0) during draft verification;
  native working-tree and copied-standalone tests exercised the new code.
- `git diff --check` passed. Independent review identified authored-UI standards,
  reduced-UI documentation, termination focus and layout gaps; the final review
  found no remaining substantive issues after their fixes. Current extraction-file
  hashes and local modification records were updated, preserving extraction hashes.

No real application was started/stopped and no product or certificate was installed,
removed or trusted by these checks. Release 0.3.0 publication was subsequently
authorized separately. Hosted workflows and a GitHub Release were not requested.
There are no new package dependencies or bundled tools.

Not established: rendered dialog behavior, ICE validation, real running-app shutdown,
installed uninstall/repair/major-upgrade acceptance, machine-policy fallback or
native ARM64 execution. The consumer application's session-ending handlers are
owned and validated separately. Follow the explicit disposable-host acceptance
matrix in [Running applications](../msi/README.md#running-applications) before release.

The supplied Agenda log documents only the app-closed successful uninstall retry;
it cannot identify the earlier unlogged stall's action or prove this change fixes
its cause. Older cached MSI databases also retain their original maintenance policy.

## Consumer-owned v2 and certificate integration — 2026-10-23

Working-tree checks before the candidate commit:

- `./msi/tests/test-config.ps1`: 49 checks, including the observed v2-schema red
  case before implementation, normalized maps, duplicate/colliding/zero GUIDs,
  scope/default combinations, architecture and missing/extra map rejection.
  Published v1 ProductCode and UpgradeCode golden values remain unchanged.
- `./msi/tests/test-msi.ps1`: all 157 existing v1 native checks pass, including
  standalone copied-engine use and x64/ARM64 tables.
- `./msi/tests/test-v2.ps1`: 151 checks across fixed machine/user, both choice
  defaults, ARM64 tables, optional-icon omission and explicit graceful policy.
  Each fixture supplies distinct literal persistent
  GUIDs and independent install/menu names. Native-host choice packages exercise
  isolated user and machine preflight sessions. Versioned framework bytes are
  copied as inert local fixtures; they are never run or redistributed.
- Twenty-eight real copied-MSI mutations cover folder names/parents/aliases,
  metadata/language, component GUID/condition, file version/language/attributes,
  native hashes, upgrade ranges/attributes/action properties, launch/search/shortcut
  fields, scope properties/maintenance condition/event ordering and summary flags.
  A preflight sentinel confirms rejection before costing; no extraction directory
  is created and the rejected input retains its original hash.
- `./tests/test-signing.ps1` includes bounded public-certificate rejection cases
  (oversize, malformed, disguised PFX, absent EKU, validity and thumbprint), source
  replacement after validation and a mocked import boundary asserting the exact
  original object. WhatIf never reaches that boundary. Keys/certificates exist only
  in memory; no persistent key or trust entry is created. The missing-reader red
  case was observed before implementation. A consumer API check then exposed
  empty optional-thumbprint forwarding; the omitted/empty reader cases were
  observed failing and now pass, while import still rejects an empty thumbprint.

The first full working-tree `./verify.ps1` reached the repository checks after
all executable suites passed and correctly rejected stale provenance hashes.
Hashes were then regenerated after CRLF normalization, preserving extraction hashes.
The pre-commit full integration run passed, including the managed fixture and a
pinned recursive consumer of baseline 9a3bf8c. A separate regression run with the
semantic comparator disabled failed at the first altered-directory mutation before
its preflight sentinel; the normal comparator passes all mutation checks. Fresh
whole-change read-only review reported no substantive findings. A post-commit full
integration run is recorded below when completed. No hosted workflow, tag, push or release is part of these checks.

Not established: rendered scope/files-in-use dialogs, ICE/ICE105, real UAC prompts,
standard-user installation, registered-context maintenance/major upgrade, running-app
shutdown/refusal, production signing/trust-chain acceptance or native ARM64 execution.
Preflight uses fresh identities, temporary targets and RM disabled, runs only the
existing explicit search/cost/InstallValidate allowlist, and never starts an install
transaction. As required by the approved plan it retains OpenPackage option 0;
restricted option 1 cannot run InstallValidate. No product is installed/removed and
no application is started/stopped. Consumers must validate the installed lifecycle
and uninstall explicitly before changing scope; synthetic checks do not prove it.

Post-commit verification of implementation `12c5e5f95b6135f47457e68608d8beeeab9a9872`:

- `./verify.ps1 -Integration` exited 0 on Windows x64 10.0.26300.0,
  PowerShell 7.6.5 and installed .NET SDK 10.0.301. All 49 configuration,
  157 v1 native and 151 v2 native checks passed, plus common/MSIX/signing/
  certificate/.NET/repository checks. The intentional never-restored .NET failure
  is a negative fixture; subsequent locked restore/build/publish/execution passed.
- The fresh recursive pinned consumer packaged and inspected its MSI using that
  exact new committed implementation, not the earlier v0.3.0 baseline.
- Fresh whole-change review found no substantive implementation issues. The
  consumer-reported optional-thumbprint forwarding bug was separately reproduced
  and fixed with absent/empty reader tests; import retains its mandatory thumbprint.
- `git diff --check` and repository provenance/help/documentation checks passed.
  This follow-up records results only; it changes no executable code or contract.
  All implementation and record commits remain local pending parent coordination;
  VERSION remains 0.3.0 with new behavior under Unreleased. No tag/release/workflow
  dispatch or remote push was performed.
