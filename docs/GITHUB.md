# GitHub publication and maintenance

This setup is local only. No GitHub repository, remote, push, release tag,
branch rules, private reporting channel or secret has been created/configured.

## First publication

1. Create an empty repository named winbuildtools in the intended GitHub account
   or organization. Choose visibility deliberately; private consumers need access.
   Do not initialize a competing README/license/history on GitHub.
2. Choose the actual owner URL and publish the existing local main branch:

   ```powershell
   git remote add origin https://github.com/OWNER/winbuildtools.git
   git push -u origin main
   ```

3. Set main as the default branch. Configure reviewer/branch protections and
   private security/conduct contact details; update SECURITY.md and the conduct
   reporting instructions. Confirm appropriate Actions permissions and Windows
   runner availability. The workflow requests contents: read only.
4. Run Actions → Verify → Run workflow against main. It runs only through
   workflow_dispatch; there are no push, PR, schedule or release triggers.
   No third-party Actions are used. The native Git checkout fetches the selected
   event SHA with ephemeral token authentication and leaves no stored credential.
5. After a clean local ./verify.ps1 -Integration and hosted verification, review
   CHANGELOG/VERSION and the public contracts, then deliberately create/push
   the first release tag (intended v0.1.0). Do not assume a release exists yet.
6. Add consumers using the published URL and an exact reviewed commit as described
   in [INTEGRATION.md](INTEGRATION.md). Confirm the referenced commit is available
   before publishing a consumer's submodule update.

Manual-only CI means checks do not start automatically on a pull request. Require
reviewers to inspect an explicitly run workflow for the intended revision. Do not
configure a required automatic check that manual dispatch cannot satisfy for the
same PR revision; select branch/ruleset policy to match the chosen manual process.

## Release discipline

Keep published historical tool commits reachable. Review public commands, JSON
schema and result fields before incompatible changes; tool release versions are
independent of application installer versions. Never make ordinary application
builds fetch a moving branch or latest release. Releases do not bundle Windows
SDK/.NET installers, application payloads or private signing materials.

The shipped verification baseline is synthetic and non-installing. Real installed
lifecycle/ICE, production signing, Store acceptance and native ARM64 execution
need additional validation before making those claims. Tool signing/trust is
separate from publication; GitHub source hosting does not establish installer trust.

See GitHub's [manual workflow guidance](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
and [token guidance](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token).
