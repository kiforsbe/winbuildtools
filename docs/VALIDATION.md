# Validation record

2026-10-20, Windows x64. This record concerns local verification; hosted GitHub
execution and actual installer lifecycle acceptance remain separate.

## Checked locally

- Extraction: at extraction, the engine implementation, schema, example JSON and
  tests matched Agenda f1586a4; license/notice/README changes were explicit
  MIT/standalone updates. [provenance.json](provenance.json) records current hashes
  and retains original extraction hashes for subsequently modified scripts.
- MSI: 29 configuration checks and 43 native synthetic checks covering x64/ARM64
  tables, cabinet bytes, stable identities, no executable custom actions, isolated read-only
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

## Native MSI wizard and registration — 2026-10-23

The owner approved the native wizard design; its saved design/plan live outside
Git under `C:/Users/kim_f/source/plans/winbuildtools-integration/`. No new runtime,
package, binary dependency or hosted workflow was introduced.

Working-tree verification:

- Configuration suite: 54 checks. Native v1: 157 checks. V2: 151 checks.
- Wizard/registration suite: 389 checks across x64/ARM64 tables/cabinet inspection,
  exact three type-51 setters, native folder memory and shortcut properties,
  native repair/remove feature events, progress mappings, modeless sequencing,
  independent control geometry/tab cycles, optional license/destination/app ID,
  and nine copied-MSI tamper cases rejected without extraction or input changes.
- RED cases observed before their fixes: absent shortcut metadata, hidden Windows
  maintenance, absent folder-memory registry row, broken tab cycles/native scope
  preview, absent native repair feature event, and destination missing from secure
  property transfer. Review additionally found unsupported reduced-UI Cancel and
  full-UI destination reset; the supported reduced behavior now disables that
  button, and destination initialization preserves explicit paths/Back edits.
- Read-only native preview succeeded for fourteen dialogs: Welcome, scope, options,
  license, Ready, maintenance, repair, remove, upgrade, progress, cancel confirmation,
  success, cancellation and failure.
  Captures were retained under ignored `artifacts/native-msi-preview/`. Visual
  inspection found readable native layout at the host's current DPI and confirmed
  literal braces/Unicode license rendering. Preview controls are inactive: this
  does not prove navigation, selection, conditional visibility or servicing.
- The acceptance helper's prepare-only mode built and inspected two fresh-identity
  packages with `LifecycleRun=false`. Supplying `-RunLifecycle` without
  `-DisposableHost` failed before creating output or starting any transaction.
  No real lifecycle mode was run.
- Fresh whole-change read-only review checked action/registry boundaries, property
  transfer, sequencing, feature events and acceptance isolation. Its substantive
  destination/reduced-UI findings were addressed; the older-custom-folder limit
  is documented explicitly rather than claimed as automatically migrated.

The initial full `./verify.ps1` passed executable suites and correctly failed on
stale provenance. Current hashes are regenerated after CRLF normalization while
preserving extraction hashes. Full integration and exact committed-consumer
results are recorded below when completed.

Not established: installed Start right-click Uninstall, live wizard navigation,
UAC/managed elevation, actual install/repair/uninstall/upgrade/rollback, keyboard/
screen reader/high contrast/scaling, ICE/ICE105, running-app behavior or native
ARM64 execution. The owner confirmed no disposable VM is available. No product,
app, persistent signing key or certificate trust was installed/removed/started/
stopped by these checks. Existing Agenda/ProcSight installations are unchanged.
Use [the acceptance guide](MSI-ACCEPTANCE.md) before shipping rebuilt consumer MSIs.

Pre-commit `./verify.ps1 -Integration` exited 0: configuration 54, v1 157, v2 151,
wizard/registration 389; all common/MSIX/signing/certificate/.NET/repository checks
passed. The intentional missing-assets .NET negative case failed as expected,
then locked restore/build/publish/execution passed. The recursive consumer used
baseline `9949d5cd95f426611ec137522d1ee76b4889677c`; it does not include uncommitted
edits. The exact committed candidate is checked separately after commit. Native
14-page preview was rebuilt from the final working-tree authoring model and all
pages rendered. `git diff --check` and 115 local document links passed.
Post-commit `./verify.ps1 -Integration` exited 0 against implementation
`675aaeb07ff3a927ae2c2411c6a1df798ff0590a` on Windows x64 10.0.26300,
PowerShell 7.6.5, Windows SDK 10.0.26100.0 and installed .NET SDK 10.0.301.
All 54 configuration, 157 v1 native, 151 v2 native and 389 wizard/registration
checks passed, as did shared/MSIX/signing/certificate/.NET/repository checks.
The fresh recursive consumer packaged and inspected its MSI from that exact
committed implementation. The expected missing-assets negative fixture preceded
successful locked restore/build/publish/execution. No installed lifecycle, trust
change or application launch/shutdown took place. Final repository checks and
`git diff --check` passed. This follow-up changes documentation only; VERSION
remains 0.3.0, new behavior is Unreleased, and no push/tag/release/Actions dispatch
was performed. Installed acceptance remains pending as listed above.
## Beta release preparation — 2026-10-23

The owner requested publication of all accumulated changes as a beta. VERSION,
current version references and the changelog now identify `0.4.0-beta.1`; the
Unreleased section remains open. The intended annotated tag and GitHub prerelease
are `v0.4.0-beta.1`. No new dependencies or executable behavior were introduced
by this release-metadata change.

`./verify.ps1 -Integration` exited 0 on the release-metadata working tree:
54 configuration, 157 v1 native, 151 v2 native and 389 wizard/registration checks,
plus common/MSIX/signing/certificate/.NET/repository checks. The fresh recursive
consumer used committed implementation/documentation baseline
`f4cf072d5d63edade2b30de1a654c0a65ff0362a`; an additional consumer check of the
release commit precedes tagging/publication. `git diff --check` passed.
Installed acceptance remains pending exactly as recorded above and is included
in the beta release notes. GitHub Actions was not dispatched. Publication uses
source archives only, without synthetic payloads or platform binary assets.
## Stable 0.4.0 release preparation — 2026-10-23

The owner explicitly requested promotion to a proper release. Version `0.4.0`
retains the beta's executable code and dependencies, updates current version and
consumer-pin references, and preserves the beta changelog/tag/release. Stable
release notes retain the same installed acceptance limitations; no additional
installed testing or lifecycle acceptance is implied by promotion.

`./verify.ps1 -Integration` exited 0 on the stable metadata working tree:
54 configuration, 157 v1 native, 151 v2 native and 389 wizard/registration checks,
plus common/MSIX/signing/certificate/.NET/repository checks and 121 local document
links. The recursive consumer used beta commit
`23aaea448133df02d182a8e5702d8c7680a99496`; the exact stable release commit receives
an additional consumer check before publication. `git diff --check` passed.
GitHub Actions was not dispatched. Publication creates an annotated `v0.4.0` tag
and a stable GitHub release; it includes no synthetic fixture/platform assets.
## Configurable native MSI presentation — 2026-10-24

The owner selected both proposed layouts and all suggested conveniences as schema
options. Both schemas now accept the strict `ui` contract in the MSI guide and
`example-ui.json`; no consumer repo/pin or release tag was changed.

Observed test-first cases: the complete presentation configuration failed schema
validation before the fields existed; native packages failed for missing Binary
resources before authoring support; review's literal-ampersand check failed before
NoPrefix text handling. Those cases passed after implementation. The first native
mutation fixture attempted MSI primary-key UPDATE, which is unsupported; it now
replaces the row while preserving all other fields, so the negative cases test
real changed launch/link/resource data rather than a fixture SQL error.

Targeted checks passed: configuration 68; existing wizard/registration 433;
presentation 969 before adding three additional image-format decode checks.
Coverage includes both schemas/layouts/architectures, exact logo bytes, native
Browse/Details, per-operation finish controls, literal text/HTTPS links, four
copied-MSI mutation cases, opt-outs, malformed/oversize/dimension/format image
rejection and native evaluation of ten launch-gate scenarios. That condition
matrix uses a fresh-identity/RM-disabled preflight copy, in-memory properties and
EvaluateCondition only, with no DoAction, navigation or launch.

Inactive native preview rendered eight pages for each layout (sixteen renders):
welcome, scope, options, Browse, Ready, completion, Details and failure. PNG captures
remain under ignored `artifacts/presentation-preview-*`. The first completion
capture reflected a host pending-restart property; explicit empty preview restart
properties then displayed the normal success/unchecked launch/links. Native edit/
list preview fields remain inactive and can be blank even when property readback
matches; this is rendering evidence, not proof of actual browsing or data entry.

A fresh whole-change read-only review found the missing NoPrefix flag for literal
ampersands; regression RED/GREEN and corrected native text authoring address it.
No further substantive issue was confirmed. Full suite/provenance/committed
consumer results are recorded below when complete. No third-party code/asset or
package/runtime dependency was added. No product/app/trust mutation occurred.

Still unverified: installed navigation, Browse OK/Cancel behavior, hyperlink
navigation, app launch identity/privileges, UAC/managed elevation, restart handling,
ICE, accessibility/scaling/high contrast, native ARM64 execution and servicing.
No disposable VM is available. Follow the expanded acceptance matrix before
shipping a rebuilt consumer package. There is no unelevated-launch guarantee.

Full working-tree `./verify.ps1 -Integration` exited 0: configuration 68, v1 157,
v2 151, wizard/registration 433 and presentation 972. The final presentation suite
also decoded PNG/JPEG/BMP/ICO fixtures successfully. All common/MSIX/signing/
certificate/.NET/repository checks and 129 local document links passed. The
intentional missing-assets .NET negative fixture failed as expected before the
locked restore/build/publish/execution passed. The fresh recursive consumer used
baseline `9d5729f6e6d3f7563d57494f968fef1a67f65a59`; exact committed-candidate
consumer verification follows below. `git diff --check` passed. No application,
product or trust entry was started/installed/removed/changed by these checks.