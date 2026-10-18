# CI scheduled teardown

`scripts/teardown.sh` is meant to run between study sessions. This workflow runs
it for you: **nightly at 03:17 UTC** it deletes the environment resource group
(`rg-oop-<env>`, e.g. `rg-oop-dev`) and purges the soft-deleted Key Vault so the
next `deploy.sh` can recreate it under the same name.

The shared resource group (`rg-oop-shared`, holding the ACR and App
Configuration) is **kept** — see [Shared RG](#shared-rg).

Setup is one-time and manual: Azure app registration + RBAC, then GitHub
environment/secrets/variables.

---

## 1. Azure: service principal and RBAC

The workflow authenticates with **OIDC workload identity federation** — there is
no client secret stored anywhere, and the credential can only be used by this
repository.

### 1.1 Create the app registration

```bash
APP_ID=$(az ad sp create-for-rbac \
  --name sp-oop-teardown \
  --query appId -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "client_id=$APP_ID"
echo "tenant_id=$TENANT_ID"
```

`create-for-rbac` does not create a password. Copy `client_id` and `tenant_id` —
both are needed below.

### 1.2 Role assignments

Assign at **subscription** scope: the environment RG is deleted by this
identity, so an RG-scoped assignment would not survive long enough to be useful,
and `--shared` targets a different RG.

```bash
SUBSCRIPTION_ID=<your subscription id>

# Use the service principal's **object id**, not the app (client) id. For this
# app they differ (appId 2c8826d7-…, objectId 281d183d-…), so assigning to
# $APP_ID succeeds but silently binds to nothing.
SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)
echo "$SP_OBJECT_ID"

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

| Role                  | Needed for                                    |
| --------------------- | --------------------------------------------- |
| Contributor           | `az group delete` on the env and shared RGs   |
| Key Vault Contributor | `az keyvault purge` on the soft-deleted vault |

Verify (RBAC propagation can take up to ~5 minutes). Check `principalId` in the
output — it must equal `$SP_OBJECT_ID`. Filtering by `--assignee` returns an empty
list here even when the assignments exist, so scope-and-filter instead:

```bash
az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --query "[?principalId=='$SP_OBJECT_ID'].{role:roleDefinitionName, scope:scope}" -o table
```

If `az keyvault purge` is refused with an authorization error, add **Owner** at
the same subscription scope — purge of a soft-deleted vault is evaluated against
the deleted resource, and some subscriptions block it for Contributor.

### 1.3 Federated credential

```bash
# Get the exact subject GitHub will present — do not hand-write it.
OWNER_ID=$(gh api repos/<your-github-user>/objective-oriented-planning --jq .owner.id)
REPO_ID=$(gh api repos/<your-github-user>/objective-oriented-planning --jq .id)

# with cred.json:
{
  "name": "oop-teardown-env-azure",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<your-github-user>@$OWNER_ID/objective-oriented-planning@$REPO_ID:environment:azure",
  "audiences": ["api://AzureADTokenExchange"]
}

az ad app federated-credential create \
  --parameters cred.json \
  --id "$APP_ID"
```

The `subject` **must** match the GitHub environment name in
[step 2](#2-github-environment-secrets-and-variables) character for character —
and the `environment:azure` segment means the subject only works if the `azure`
environment exists and is attached to the job.

GitHub includes the **numeric owner and repo ids** in the subject
(`repo:owner@12345/repo@67890:environment:azure`). The older id-less form
(`repo:owner/repo:environment:azure`) is not what is presented any more, and
login fails with:

```
AADSTS700213: No matching federated identity record found for presented
assertion subject 'repo:...'
```

Get the ids with `gh api repos/<owner>/<repo> --jq .id` (and `.owner.id`) as
above. If an id-less credential already exists it can be deleted:

```bash
az ad app federated-credential delete --id "$APP_ID" \
  --parameters oop-teardown-main
```

---

## 2. GitHub: environment, secrets and variables

Repo → **Settings** → **Environments** → **New environment**, named `azure`.

Add **secrets**:

| Name                    | Value                              |
| ----------------------- | ---------------------------------- |
| `AZURE_SUBSCRIPTION_ID` | Subscription containing `rg-oop-*` |
| `AZURE_CLIENT_ID`       | app id from 1.1                    |
| `AZURE_TENANT_ID`       | tenant id from 1.1                 |

All three must be **secrets**, not variables — the workflow reads them via
`${{ secrets.* }}`. Stored as variables the OIDC login step gets empty values and
fails with `Not all values are present. Ensure 'client-id' and 'tenant-id' are
supplied`.

Repository-level secrets work too (an environment secret shadows a repository one,
and `${{ secrets.* }}` falls back to repository scope), so `AZURE_CLIENT_ID` /
`AZURE_TENANT_ID` may live under **Settings → Secrets and variables → Actions →
Secrets** instead. `AZURE_SUBSCRIPTION_ID` is the one to keep on the `azure`
environment, since it is subscription-specific.

```bash
# sanity check that all three resolve, after saving them
gh secret list
gh secret list --env azure
```

Add **variables** (Settings → Secrets and variables → Actions → Variables tab):

| Name          | Value        | Notes                    |
| ------------- | ------------ | ------------------------ |
| `BASE_NAME`   | `oop`        | must match your `.env`   |
| `LOCATION`    | `westeurope` | must match your `.env`   |
| `ENVIRONMENT` | `dev`        | fallback for manual runs |

Note `AZURE_CLIENT_ID` and `AZURE_TENANT_ID` are **secrets** while `BASE_NAME`
and `LOCATION` are **variables** — deliberately. The subscription, client and
tenant are credentials; the base name and region are configuration and are useful
to read in the Actions UI.

### Shared RG

`rg-oop-shared` is **never** deleted by a scheduled run. `teardown.sh` only
removes it when passed `--shared`, and the workflow passes it only when the
`delete_shared` input is set **and** the `SHARED_LOCK` repo variable is not
`true`. The manual `purge_vault` input governs the vault; the shared group's fate
is otherwise a deliberate local decision, because it is the only always-on cost
and rebuilding it means re-pushing every image.

---

## 3. First run

1. Trigger **Actions → teardown → Run workflow**.
   With nothing deployed, `--precheck` reports both absent and the job goes green
   having touched nothing in Azure. That is the expected common case.
2. Deploy (`./scripts/deploy.sh`), then run the workflow again. Expect the RG
   delete, the vault purge, and a green **Verify** step.
3. Confirm in the portal that `rg-oop-dev` is gone and `rg-oop-shared` still
   exists.
4. Confirm the next `./scripts/deploy.sh` succeeds — that is the real proof the
   vault was purged (an un-purged vault blocks the same name).

---

## 4. Pausing / operating

- **Pause the nightlies:** GitHub → repo → Actions → `teardown` →
  **Disable workflow**. Re-enable before your next study session. The workflow is
  cost-control infrastructure; disabling it defeats its only purpose.
- **Rebuild:** `./scripts/deploy.sh` (plus `./scripts/deploy-shared.sh` if the
  shared RG is gone).
- **Long inactivity:** GitHub disables scheduled workflows on repos with no
  activity for 60 days, so the nightly simply stops running. Check the Actions
  tab after a long break.
- **Rerun the verification:** rerun the whole job; the RG delete is a no-op when
  the group is absent, and `--precheck` skips it. Or locally:
  `./scripts/teardown.sh --verify` (read-only, no Azure mutation) — shorten it
  with `RG_VERIFY_WAIT_MINUTES=5` when you only want a quick answer.
- **Check the drain yourself:** `./scripts/check-state.sh --rg rg-oop-<env>`
  prints the group's provisioning state and every resource's state, with the
  verdict in the exit code. That is exactly what `--verify` prints every 10 min —
  and it appends the same as a markdown table to the run summary when the
  nightly workflow passes `--summary`.
- **Read the run summary, not the log:** every nightly run ends with a table
  answering the only question that matters — is the group gone, is the vault
  unblocked, did verify pass — rendered above the log on the run's summary page.
- **Dry run the workflow:** set the `dry_run` input. It stops after the pre-check
  and prints the resource group, vault and shared-RG decisions without touching
  Azure.

---

## 5. Troubleshooting

| Symptom                                              | Cause / fix                                                                                                                                                                                           |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AADSTS70021: No matching federated identity record` | Federated-credential `subject` does not match `repo:<owner>@<id>/<repo>@<id>:environment:azure`                                                                                                       |
| `AADSTS700213` on login                              | Subject is missing the numeric owner/repo ids                                                                                                                                                         |
| `AuthorizationFailed` on `az group delete`           | Role assignment missing or not yet propagated (~5 min). Re-check with the verify command in 1.2                                                                                                       |
| Role assignment created but binds to nothing         | You assigned the app (client) id instead of the service principal's object id                                                                                                                         |
| `Forbidden` on `az keyvault purge`                   | Add **Owner** at subscription scope (see 1.2)                                                                                                                                                         |
| Verify step: `still soft-deleted`                    | Purge raced the RG delete. Purge manually: `az keyvault purge --name kv-oop-dev`                                                                                                                      |
| Verify step: RG still exists                         | The managed environment is slow to drain — ~16 min observed on the first real nightly run. `--verify` polls for ~40 min and prints what is left draining via `check-state.sh --rg`; do not shorten it |
| Verify step: vault still soft-deleted                | The destroy step skipped the purge because the vault was briefly neither live nor soft-deleted. Fixed in PR #5 (`VAULT_WAS_LIVE` guard). If it recurs, purge manually with the command printed        |
| Red run, console shows no detail                     | The **Upload script logs** artifact holds the command/stdout/stderr transcripts the console hides. Download it from the run summary                                                                   |
| Red run: `Vault did not become soft-deleted`         | `VAULT_PURGE_WAIT_MINUTES` (5 in the workflow) was too short for this drain. Re-run the job, or purge manually with the command printed                                                               |
| Run summary empty, or later steps swallowed          | `teardown.sh --verify` writes the run summary via `summary`; the GitHub backend renders `step` as `##` and `group` as `<details>`. An unclosed `group` swallows everything after it                   |
| `scripts/check-state.sh` exits 64                    | Usage error, not a health verdict — a bad flag, or `--rg` with no group name. `--rg` also exits 0/1/2 by design; see § 6                                                                              |
| Verify step: vault still soft-deleted                | The destroy step skipped the purge because the vault was briefly neither live nor soft-deleted. Fixed in PR #5 (`VAULT_WAS_LIVE` guard). If it recurs, purge manually with the command printed        |
| Job silently did nothing                             | Nightly schedule disabled (60-day inactivity) or workflow disabled in the Actions tab                                                                                                                 |
| `BASE_NAME: parameter null` style script errors      | `scripts/common.sh` requires `BASE_NAME`/`LOCATION`/`SUBSCRIPTION_ID`; confirm the GitHub variables exist                                                                                             |

---

## 6. Related

- [`scripts/teardown.sh`](../scripts/teardown.sh) — the script this workflow calls
  (flags: `--purge-vault`, `--shared`, `--precheck`, `--verify`)
- [`scripts/common.sh`](../scripts/common.sh) — naming rules
  (`rg-oop-<env>`, `kv-oop-<env>`, `rg-oop-shared`); it sources the two utilities
  below rather than holding their code
- [`scripts/_log.sh`](../scripts/_log.sh) — logging backends plus the `run`
  command logger and the three files written to `logs/`
- [`scripts/_azure.sh`](../scripts/_azure.sh) — `az` probes: `subscription_name`,
  `group_exists`, `vault_is_live`/`vault_is_soft_deleted`,
  `fetch_deployment_outputs`
- [`scripts/check-state.sh`](../scripts/check-state.sh) — read-only provisioning
  check; exits non-zero when anything is not Succeeded. `--rg <name>` reports one
  group and answers in its exit code (0 absent / 1 not Succeeded / 2 all
  Succeeded), which is how `--verify` narrates a drain; `--summary` adds the same
  as markdown for the run summary
- [`scripts/check-logging.sh`](../scripts/check-logging.sh) — drives every
  printer through both backends offline and asserts where each message lands; a
  CI gate
- [`docs/architecture.md`](architecture.md) — what lives in which group, and why
- [`PLAN.md`](PLAN.md) § Cost & safety — the cost model this workflow protects
