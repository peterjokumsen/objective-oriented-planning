# Phase 1 · Step 8 — `scripts/deploy.sh`

**Ported from `~/repos/memorywell/scripts/deploy.sh`.** The environment deploy:
Bicep, then image build, then repoint the app, then prove it answers.

The shape is five guards and three `az` calls, and the guards are most of the
value — each one exists because the failure it prevents is confusing.

## Guards, in order

1. **Shared group exists**, and `az acr show` succeeds — `az group show` alone
   proves nothing if the registry is missing. Fail with
   `./scripts/deploy-shared.sh create`.
2. **Env RG not in `Deleting`.** `deploy.sh` deletes with `--no-wait` (step 9),
   so the managed environment drains slowly and the RG lingers; a Bicep
   sub-deploy in that window fails. Report `absent` and continue — that is the
   first-deploy case, not an error.
3. **Image tag check**, and this one **tolerates failure**: if
   `az acr repository show-tags --repository api` contains `$ENVIRONMENT`,
   export the real image; otherwise warn and fall back to
   `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`.

## The three calls

```bash
az deployment sub "$ACTION" \
  --location "$LOCATION" \
  --name "$DEPLOYMENT_NAME" \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

Then read `registryName`, `loginServer`, `appName`, `fqdn` (plus
`appConfigStoreName`, `appConfigEndpoint`) from `az deployment sub show`, and
assert the login server matches. Exit early on `what-if`.

```bash
az acr build -r "$REGISTRY" -t api:$ENVIRONMENT -t api:$IMAGE_TAG ./api
az containerapp update --name "$APP_NAME" --resource-group $RG_NAME \
  --image "$LOGIN_SERVER/api:$IMAGE_TAG"
```

Two tags for two different jobs: the floating `api:dev` is what guard 3 finds on
the next run, and the unique `api:dev-<timestamp>` is what changes the template
string and forces a new revision. Both matter; dropping the unique one is the
single most likely way this phase fails its gate.

**Do not add `revisionMode` to the container app.** It is tempting — the first
deploy can leave a single revision, which looks like single-revision mode. It is
not: `az containerapp update --image` on a plain change mints a new revision
regardless, and adding `revisionMode: 'Multiple'` is rejected by Bicep's type
checker on every API version that has types (BCP037), which fails the whole
deployment. Verified empirically on `2025-07-01`.

If a first deploy shows one revision, it is a timing artefact — the Bicep create
and the `containerapp update` raced the app's initial provisioning. Confirm by
deploying again before changing anything; the second deploy should add a
revision.

Note the order: `acr build` first, then `containerapp update`. A tag that
repoints the app before it exists pulls nothing and the app stalls.

## Health check

Poll `https://${FQDN}/health` with `curl -sSf --max-time 5`, sleep 5, 12
attempts — about 60s, which covers an ACR pull plus scale-from-zero on the
Consumption plan. Fail with the attempt count, not a bare curl error.

Exceeding 60s on a genuinely cold start is plausible; exceed it repeatedly and
check the container app's revision state in the portal before assuming the
image is bad.

## Verify

- `bash -n` and shellcheck clean.
- `./scripts/deploy.sh what-if` from an absent env RG lists every creation in
  `rg-oop-dev` plus the role assignment in `rg-oop-shared`.
- `./scripts/deploy.sh` succeeds and prints the FQDN, and the health poll
  eventually returns `{"status":"ok"}`. Note how many attempts it took — that
  number becomes the realistic first-startup expectation.
- `az containerapp revision list --name ca-oop-dev --resource-group rg-oop-dev
--output table` shows **two or more** revisions, the latest active at weight 100. One revision means the timestamped tag is not reaching
  `containerapp update`.
- `az acr repository show-tags -n acroop --repository api` lists both `dev` and
  `dev-<timestamp>`.
- Run `./scripts/deploy.sh` a second time: a third revision appears. That is
  revision management proven rather than assumed.
