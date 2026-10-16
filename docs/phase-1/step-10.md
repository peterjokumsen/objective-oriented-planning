# Phase 1 · Step 10 — Arm the nightly workflow, write `docs/CI_TEARDOWN.md`

Two deliverables, and the order matters: **the doc first**. The workflow is
currently an inert skeleton whose every step is `echo "to be implemented"`, and
arming it before the OIDC setup is written down is how a credential problem turns
into an hour of debugging.

## `docs/CI_TEARDOWN.md`

Ported from `~/repos/memorywell/docs/CI_TEARDOWN.md` and rewritten for this repo.
Keep its structure — it is genuinely good, and the § 5 troubleshooting table is
the part that pays off later:

1. **Azure: app registration + RBAC.** `az ad sp create-for-rbac` (creates no
   password), `Contributor` and `Key Vault Contributor` at **subscription**
   scope. The sharpest detail to carry over: assign the service principal's
   **object id**, not the app (client) id — assigning to `$APP_ID` succeeds and
   silently binds to nothing. Verify with a scope-and-filter `az role assignment
list`, because `--assignee` returns empty even when the assignments exist.
2. **Federated credential.** The `subject` must contain the **numeric owner and
   repo ids** (`repo:<owner>@<id>/<repo>@<id>:environment:azure`) — the older
   id-less form fails with `AADSTS700213`. Get them from
   `gh api repos/<owner>/<repo> --jq .id`. Note that `environment:azure` means
   the credential only works if that environment exists and is attached.
3. **GitHub environment `azure`:** secrets `AZURE_SUBSCRIPTION_ID`,
   `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`; variables `BASE_NAME=oop`,
   `LOCATION`, `ENVIRONMENT=dev`.
4. **First run:** dispatch with the pre-check, then apply, then confirm in the
   portal that `rg-oop-dev` is gone and `rg-oop-shared` remains, then prove the
   next `./scripts/deploy.sh` succeeds.
5. **Operating and troubleshooting**, including that GitHub disables scheduled
   workflows after 60 days of repo inactivity.

Update every `memwell` reference to `oop`, and drop the `SHARED_LOCK` section —
this repo's `teardown.yml` has no such variable and `teardown.sh --shared` is
opt-in only. Do not document a variable the workflow does not read.

## Arm `.github/workflows/teardown.yml`

Replace each placeholder with the command its comment already names, and delete
the comment that says "becomes" once it is true. `permissions` and `concurrency`
are already correct — `id-token: write`, and `cancel-in-progress: false` so two
teardowns cannot race.

- **Log in** → `uses: azure/login@v2` with `client-id: ${{ vars.AZURE_CLIENT_ID }}`,
  `tenant-id: ${{ vars.AZURE_TENANT_ID }}`,
  `subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}`. Note these come from
  `vars`, not `secrets` — the workflow's env block already reads
  `AZURE_SUBSCRIPTION_ID` from `secrets`. Pick one convention and make the doc
  match it.
- **Pre-check** → `./scripts/teardown.sh --precheck`, with the destructive steps
  gated on a step output (skipped when nothing exists).
- **Destroy** → `./scripts/teardown.sh --purge-vault`. Nightly runs purge;
  local runs keep it opt-in because RG deletion is async.
- **Verify** → `./scripts/teardown.sh --verify`. Raise `timeout-minutes` from 30
  if the managed environment proves slow to drain — memorywell needed 45.

Keep the file's existing header comment. The paragraph about it being cost-control
infrastructure that must never be deleted is the most valuable thing in it.

Two things to preserve deliberately: the `environment_name` and `purge_vault`
dispatch inputs already exist, and the `PurgeVault` input should map onto
`--purge-vault` rather than being ignored.

## Verify

- `bash -n scripts/teardown.sh`; the workflow file parses
  (`pre-commit run --files .github/workflows/teardown.yml` covers check-yaml).
- `grep -c "to be implemented" .github/workflows/teardown.yml` returns **0**.
- `grep -n "az group delete" .github/workflows/teardown.yml` returns nothing —
  the workflow must delegate to the script, never inline a delete. The script has
  the pre-check and the verification; a raw `az group delete` here would have
  neither.
- `grep -rn "memwell" docs/ .github/ scripts/ infra/ api/` returns nothing.
- The pre-check branch taken on a real dispatch: the destructive steps report as
  skipped and the job is green, with `rg-oop-dev` still absent afterwards.
