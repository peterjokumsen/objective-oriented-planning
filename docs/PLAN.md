# Objective-Oriented Planning - Plan

An application where a user declares a single objective and AI helps prepare the
steps needed to achieve it (see `INITIAL_IDEA.md`). One plan is one objective;
the steps are themselves objectives, forming a recursive tree. Other people
join as **helpers** (own a subtree) or **observers** (read-only, filtered). AI
clarifies vague objectives, proposes a breakdown with weights, and coaches
stalled work. Every objective is SMART, so recurring work is a _bounded block_
that resolves to successful / partial / missed and can be renewed.

> **Status:** `migrated` — this is now the **working copy**. The think-tank copy
> at `~/repos/think-tank/objective-oriented-planning/PLAN.md` is a frozen record
> of what was decided before any code was written; this file is what the build
> actually follows and may be edited as the plan is realised.
> **Build repo:** `~/repos/objective-oriented-planning`
> (github.com/peterjokumsen/objective-oriented-planning) — **Phase 1 in
> progress**; brief at `docs/phase-1/_brief.md`, no application code yet.
>
> New ideas about where the project should go do **not** belong here — they go
> in `~/repos/think-tank/objective-oriented-planning/FUTURE.md`. A change to
> scope, architecture, phase order or domain rules _is_ a change to this file.

---

## Decisions

| Topic                         | Decision                                                                                                                                                                                                              |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Plan shape                    | One plan = one declared objective; recursive objective tree inside it                                                                                                                                                 |
| Weight                        | Owner-declared, stored on the **parent-child relationship** only; an objective has no concept of its own weight                                                                                                       |
| Weight authorship             | AI suggests, owner adjusts and is the only party who may write a child's weight                                                                                                                                       |
| Rollup                        | Weighted: `parentPercent = Σ(childPercent × childWeight) / Σ(childWeight)`                                                                                                                                            |
| Abandoned children            | Excluded from the rollup denominator, always displayed (`n of m abandoned`) so exclusions stay visible                                                                                                                |
| Abandon authority             | Helper may abandon objectives in their own subtree; owner may abandon anywhere                                                                                                                                        |
| Abandoned plan                | **Excluded from rollup entirely** — renders as `abandoned` with no percent. Archived keeps its percent; the two states differ deliberately                                                                            |
| Empty plan / childless parent | Rollup is `null`, rendered `—`. Distinguishes "nothing defined yet" from "defined, nothing done"                                                                                                                      |
| Progress                      | Status + optional weekly weighted percent rollup; repeatables contribute a computed completion rate                                                                                                                   |
| Repeatables                   | Bounded SMART **blocks** (cadence + target + start + end date), never open-ended habits                                                                                                                               |
| Cadences                      | `daily`, `weekdays`, `n-per-week`, `monthly`                                                                                                                                                                          |
| Block resolution              | On read: end date passed + log meets target → `successful`; ≥50% → `partial`; else `missed`                                                                                                                           |
| Renewal                       | A resolved repeatable can be renewed into a fresh block, linking (not copying) prior history                                                                                                                          |
| Archive vs renew              | **Decoupled.** Archiving a plan never renews anything; bulk renew is a separate, explicit owner action taken beforehand                                                                                               |
| Timezone                      | One IANA zone per **plan**, owner-set at creation and editable. Governs cadence day boundaries, `endDate`, and "today is pending". Changing it affects future boundaries only — already-scored verdicts are immutable |
| Concurrency                   | **Optimistic concurrency on every write** (`_etag`). Mismatch → `409` + client refetch. No last-write-wins anywhere                                                                                                   |
| Inactivity rule               | **Any write** to an objective resets its clock — status, detail, clarifying answers, or an occurrence log                                                                                                             |
| Rollup caching                | Short-TTL cache on reads only. Any write response recomputes from Cosmos; never serve a cached percent after a write                                                                                                  |
| Occurrence storage            | Occurrences live in the single `planId`-partitioned container, filtered client-side by `objectiveId`. Documented split threshold below                                                                                |
| AI scope                      | One coaching agent: clarify → decompose (staged proposals) → coach (dismissible cards)                                                                                                                                |
| AI trigger                    | On-demand only; unattended scheduled coaching **deferred** to Phase 6                                                                                                                                                 |
| Deployment                    | Cheapest viable Azure subset: Cosmos serverless, Container Apps scale-to-zero, Key Vault, ACR, App Configuration                                                                                                      |
| Not included initially        | Postgres, Redis, Service Bus, Event Grid, Functions — added only when a phase needs them                                                                                                                              |
| Shared resources              | ACR + App Configuration live in `rg-oop-shared`, not per-environment                                                                                                                                                  |
| Config                        | `config.py` with typed defaults, env-overridable; App Configuration keys namespaced `dev.*` / `prod.*`                                                                                                                |
| Auth                          | Owner = real account (Microsoft). Helpers = magic-link invite, optional self-service account upgrade that links the same participant                                                                                  |
| Roles                         | Owner / Helper / Observer, all scoped to a single plan                                                                                                                                                                |
| Observer visibility           | One tier per observer, whole plan: **`progress`** or **`full`**. Renders from an **allowlist**, so fields added in later phases are hidden until deliberately exposed                                                 |
| Observer names                | Helper names are **hidden at `progress`**, visible at `full`                                                                                                                                                          |
| Observer coach cards          | Hidden at `progress`, visible at `full`                                                                                                                                                                               |
| Observer no-grant             | A deliberate selection, not an oversight: **"no restrictions" shows the whole plan** at the observer's tier. Distinct from granting the root, which shows the root alone                                              |
| Notes                         | First-class `note` entity on an objective. **Phase 4 deliverable**, alongside the UI that renders them                                                                                                                |
| Item visibility               | Notes, detail text and clarifying answers each carry a **public / private** flag, set by their author. This is a decision made _at write time_, independent of who reads it later                                     |
| Private items                 | Private means **hidden from `progress` observers, visible at `full`**. The tier remains load-bearing — it decides what private even means                                                                             |
| Visibility authorship         | The author sets the flag on their own items; the owner may override any item's flag. Nobody else may re-classify another's writing                                                                                    |
| Occurrence logs               | Carry **no** flag. Logging a walk is an act, not a statement, and hiding it would make a block's own arithmetic unexplainable to observers                                                                            |
| Observer `full`               | Not a separate allowlist. Defined as **"see exactly what a helper sees, read-only"** — it inherits the helper read surface, so new fields need auditing once, not twice                                               |
| Observer `progress`           | Means **public only**: authored fields (detail, answers, notes) render iff `isPublic`. Also hides the two things nobody authored — helper names and coach cards                                                       |
| Observer `full`               | Read-only helper. Sees everything a helper sees, including private items, and writes nothing                                                                                                                          |
| Observer grants               | Per-node allowlist, **no subtree inheritance**. May be left empty, which means **the whole plan** at the observer's tier — an explicit choice, not an absence                                                         |
| Redaction                     | Per-observer **denyList** of objectives whose title and details are hidden while progress still shows, labelled `redacted`. Subtracts from whatever grants allow                                                      |
| Grant vs denyList             | An objective is **visible iff granted (or grants are empty) AND not denied**. Redaction always wins                                                                                                                   |
| Redaction cascade             | Redacting an objective redacts its **whole subtree**. A visible child would otherwise reveal its redacted parent                                                                                                      |
| Redaction authority           | A helper may redact inside **their own subtree** only; the owner may redact anywhere. Mirrors abandon authority                                                                                                       |
| Redacted in rollup            | A redacted objective **still counts in the parent rollup**. Excluding it would make the percentages stop adding up                                                                                                    |
| Display mode                  | **Light / dark / system**, a _per-user_ preference. Client-side only, resolved from `prefers-color-scheme` by default, and **not recorded server-side** — it is not a participant field                               |
| Plan aesthetics               | **Colour theme and font-family**, set by the owner on the plan and stored server-side. Distinct from display mode: this is the plan's identity, not the reader's                                                      |
| IaC                           | Bicep                                                                                                                                                                                                                 |
| Formatting                    | `pre-commit` + `.editorconfig`, wired in the **first commit** (not retrofitted)                                                                                                                                       |
| Teardown                      | `scripts/teardown.sh` from Phase 1, plus a nightly scheduled CI teardown with a cheap pre-check                                                                                                                       |

---

## Architecture -> Azure component mapping

Deliberately minimal. Each component below is justified by a phase that needs
it; nothing is provisioned "for later".

### Data

- **Azure Cosmos DB for NoSQL** (serverless): the whole domain model in one
  container. Partition key `planId` — every read is scoped to a plan, and
  everything in the app is plan-scoped, so this is the natural tenant boundary
  even with one plan per deployment.
  - `plan`: root objective + lifecycle state + settings, including
    **`timezone`** (IANA) and archived/abandoned state
  - `objective`: tree node — `parentId`, `weightInParent`, title, `detail` and
    `clarifyingAnswers` (each carrying an **`isPublic`** flag), cadence fields
    for repeatables, lifecycle, and **`createdAt` / `updatedAt` / `_etag`** on
    every row
  - `participant`: `participantId` (stable key), planId, email, displayName,
    role, `subtreeRootId` (helpers), and for observers `visibilityTier`,
    **`grantedObjectiveIds[]`** (empty = unrestricted) and
    **`redactedObjectiveIds[]`** (empty = nothing withheld), `authMethod`
  - `occurrence`: one row per completed repeat — `occurredAt`, `helperId`,
    `objectiveId` (filter key, see below)
  - `note`: free-text note attached to an objective, authored by a helper or
    owner, carrying an **`isPublic`** flag. **Phase 4** — see _App experience_
    and the phase table
  - `proposal`: staged AI decomposition / upward edits awaiting owner approval
  - `coachCard`: dismissible suggestion attached to an objective
  - Vector/policy tuning is **not** provisioned up front. If the coach ever
    needs semantic recall over past objectives, an indexing policy change is
    one Bicep edit at that point.
- No Postgres and no Redis in the initial cut. Rollup and block scoring are pure
  functions over a plan's objectives.

#### Occurrence partitioning and the split threshold

Occurrences share the `planId` partition with everything else. Loading a
single repeatable's log is therefore a **cross-partition scan filtered in
process**, not a point read.

This is the right trade at v1: one container, one Bicep module, one read path.
It stops being right at a stated threshold, recorded here so the decision is
deliberate rather than discovered:

> **Split when a single repeatable exceeds ~5,000 occurrences, or a plan
> exceeds ~50,000 objectives total.** At that point add a second container with
> partition key `/objectiveId` and move `occurrence` into it.

Record the threshold in `docs/architecture.md` when that file is written, and
revisit it if the app is ever used for more than a handful of concurrent plans.

### App

- **Azure Container Apps**: FastAPI backend + static frontend, `minReplicas: 0`
  so nothing runs between study sessions. Revision management from day one.
- **Azure Container Registry** + **ACR Tasks**: image build and push.
- **App Service Easy Auth**: Microsoft sign-in for the owner's real account.
  Helpers who only ever claim a magic link never touch this.

### Config & secrets

- **Azure Key Vault**: invite-signing secret and any future credential. Managed
  identity + Key Vault references in Container Apps; secrets never in the repo.
- **Azure App Configuration** (shared, one store for all environments):
  coach thresholds and feature flags, keys namespaced per environment
  (`dev.coach.inactivityDays`, `prod.coach.inactivityDays`). One store rather
  than one per RG is what makes this cheap and is why it belongs in the shared
  resource group alongside ACR. Free-tier limits (1,000 requests/day) are
  comfortable at this scale; dev and prod share that quota.

### Deliberately absent

Postgres/pgvector, Managed Redis, Service Bus, Event Grid, and Functions are
all excluded until a phase requires them. The single planned addition is the
Phase 6 scheduled coach sweep, and even that uses the smallest thing available
(Azure Container Apps Job on a daily schedule) rather than opening the messaging
stack.

---

## The objective tree

### Timestamps and concurrency

Every objective row carries `createdAt`, `updatedAt`, and Cosmos `_etag`.

- `updatedAt` is not metadata — it is the **input to the coach's inactivity
  rule**. Without it, "a leaf `in progress` with no update for N days" is
  unimplementable, and the coach cannot distinguish genuine silence from a
  system with no timestamps.
- **Any write** resets the clock: status change, detail edit, clarifying answer,
  or logging an occurrence. The rule is deliberately generous — you are coached
  on silence, not on slowness.
- **Every write path sends the `_etag` it read.** On mismatch the API returns
  `409` and the client refetches. There is no last-write-wins path anywhere in
  the app, including the progress updates two helpers might make to the same
  leaf.

This is cheap in Phase 2 and expensive to retrofit: retrofitting etags after
real concurrent use has produced lost updates means reconciling data.

### Stale writes are presented, not rejected

A `409` on an ordinary edit is correct — the user changed something and should
see the current state before reapplying. But **approving a proposal is not an
ordinary edit**, and erroring there is the wrong shape.

A `proposal` is staged, so the objective it targets can change arbitrarily
between the proposal being raised and the owner getting to it. The owner
clicking approve and receiving a `409` is a dead end: there is no obvious
"retry" that means anything.

Instead, when the `_etag` has moved, the approval flow **shows what changed**
and lets the owner decide:

- The inbox shows the proposal alongside the objective's current state.
- On a stale `_etag`, the differences between the proposal's basis and the
  objective as it now stands are **rendered for the owner to review**.
- The owner then re-approves against the current version, or abandons the
  proposal. Neither path loses the proposal or silently discards the change.

The rule is general: `409` protects data, but any flow where the user has
already made a considered decision gets **surfaced as a review step**, never as
an error. Approving a proposal is the first such flow; Phase 5 may find others.

Phase 2 builds the mechanism (`409` + a diff endpoint); Phase 5 builds the
presentation. Recording it here so Phase 5 does not discover it as a dead end.

### Weight lives on the relationship

An objective has no weight of its own. Its parent declares "this child is worth
3 relative to its siblings". Consequences worth keeping explicit:

- The number is stored on the child's row (denormalized) for simplicity, but
  **only the parent's owner may write it**. A helper cannot re-weight themselves
  or a sibling they do not own.
- Two helpers looking at the same objective can legitimately see different
  relative importance for it, depending on whose child it is.

### Rollup

```text
objective.percent = Σ over children of (child.percent × child.weight) / Σ child.weight
```

- Root carries no weight; it is the weighted average of its children.
- **Unassigned children count in the denominator at 0%.** An unclaimed step
  visibly drags the root down — that is the intended pressure.
- **Abandoned children are excluded** from both numerator and denominator, and
  surfaced as `n of m abandoned` beside the percent. Excluding without showing
  would let the number be gamed by abandoning the hardest work.
- **A childless parent is `null`, not 0%.** It renders as `—`. A plan whose
  breakdown has not been accepted yet is in a genuinely different state from
  one whose steps are all unstarted, and `0%` cannot express that difference.
- **An abandoned plan has no percent at all.** It renders as `abandoned`. This
  is the deliberate asymmetry with `archived`, which keeps its percent as a
  record of how far it got.

### Caching

Rollups are pure functions over a plan's objectives, cheap at plan scale. They
are cached with a **short TTL on reads only** — enough to absorb a
read-heavy tree view, not a source of truth.

**Any write response recomputes from Cosmos.** A percent returned immediately
after an edit is never a cached one. In-process caching across Container Apps
replicas is unsafe as a correctness source, so cache for rendering, never for
correctness.

### Completion

A parent is **complete when nothing is in flight** — every non-abandoned child
is `done`, `successful`, or `missed`. The parent's own outcome is `successful`
if all its children succeeded, `partial` if some missed. One rule, no special
case for repeatables.

---

## Repeatables as bounded blocks

The unit of recurrence is a finite block, not an open-ended habit:

> Walk 5 minutes a day, 5 days per week, from 3 Nov to 13 Dec.

- **Fields**: `cadence`, `targetCount`, `startDate`, `endDate`. `targetCount` and
  `endDate` are **required** — this is what makes SMART structural rather than
  aspirational.
- **States**: `in flight` (start reached, end not yet passed) → `resolved`
  (end date passed, scored).
- **Scoring is derived on read**, never stored, and needs no scheduled job:
  - Excess does not overflow — 7 walks against a target of 5 reads as 100%.
  - Today is not a miss yet — an occurrence with no log today is _pending_, so
    the percent does not swing wildly between morning and evening.
- **Verdicts**: `successful` (target met), `partial` (≥ 50%), `missed`.
  Partial credit is preserved because 21-of-25 and 4-of-25 are different stories
  and the plan should not treat them alike. Partial blocks weight normally in
  the parent rollup.
- **Repeatables are leaves.** "Go to the gym" decomposes; "walk every day" does
  not. Enforced, not merely conventional.

### Timezone

Every cadence calculation is performed in the **plan's** IANA timezone, stored
on the plan and editable by the owner at any time.

- One zone per plan, not per participant. A shared plan with helpers in
  different zones needs a single reference for "today" — otherwise the same
  block scores differently depending on who opens it.
- The zone governs cadence day boundaries, the meaning of `endDate`, and the
  "today is pending, not failed" rule.
- **Changing the zone affects future day boundaries only.** A block whose verdict
  has already been computed keeps that verdict. History is not rewritten by a
  configuration change.
- The zone is validated against the IANA list at write time, so a typo cannot
  make a plan unscoreable.

### Renewal

A resolved block can be **renewed** into a fresh block.

- **History links, it does not copy.** The occurrence log stays with the original
  plan; the renewed block renders as _"continuing — 21/25 in the prior block
  (3 Nov – 13 Dec)"_. Copying logs would create two sources of truth for the
  same days.
- Available per-objective (the normal case) **and** in bulk when a plan is
  archived or abandoned (the convenience).

### Renewal is independent of archiving

**Archiving a plan never renews anything.** Bulk renewal is a separate,
explicit owner action, taken _before_ archiving if that is what the owner
wants.

A freeze and a mutation are different intents, and bundling them means the
owner cannot archive without also deciding to renew every in-flight block. Two
deliberate steps instead of one ambiguous one.

The App experience section therefore offers bulk renew and archive as two
adjacent buttons, not one.

### Renewal is why deferring automation pays off twice

Both the in-flight completion rate and the resolved verdict are computed from
`occurredAt` at read time. A block that ended last week is already scored the
first time it is opened. There is no window to roll over and no verdict to
finalize on a schedule — so the absence of a timer costs nothing here.

---

## Roles and permissions

- **Owner** — creates the plan; assigns helpers; writes weights; approves or
  rejects proposals; sets observer tiers, grants and denyLists anywhere in the
  tree; archives or abandons the plan. Only the parent owner may write a child's
  weight.
- **Helper** — edits freely **inside their own subtree**. Everything above their
  assignment is read-only except `proposal` rows they raise for owner approval.
  May abandon objectives in their subtree, including a repeatable block (which
  stops the recurrence but keeps the partial log visible). May also **redact**
  objectives in their subtree from individual observers — the same subtree scope
  as abandoning, by the same rule.
- **Observer** — read-only, and filtered three ways. **Grants** decide which
  objectives may be visible (empty = all); the **denyList** subtracts from that;
  the **tier** decides how much is exposed. All applied server-side. At
  `progress`, additionally sees only public authored items.

Enforcement is server-side. The client hides what a participant cannot do; it is
never the thing that decides.

### Observer visibility — tier and denyList

An observer's view is determined by **three orthogonal filters**, all applied
server-side:

| Filter        | Question it answers                                   | Set by                                  | When          |
| ------------- | ----------------------------------------------------- | --------------------------------------- | ------------- |
| **Grants**    | _Which_ objectives may be visible at all?             | Owner, per node                         | Anytime       |
| **DenyList**  | _Which_ of those are withheld?                        | Owner, or a helper in their own subtree | Anytime       |
| **Tier**      | _Who_ is reading, and how much does the tier expose?  | Owner, whole plan                       | At invite     |
| **Item flag** | _Which_ authored items did their author mark private? | Author (owner may override)             | At write time |

The composition rule is one line, and everything else follows from it:

> **Visible iff (granted OR grants are empty) AND NOT denied.**
> Redaction always wins.

Grants and denyList answer the same question from opposite directions — _which
objectives_ — which is why they compose as subtraction rather than as two
independent filters. The tier and the item flag answer a different question,
_what is in them_, and neither constrains which objectives appear.

#### Tier: `progress` and `full`

`full` means **"see exactly what a helper sees, and write nothing"** — a
read-only helper. It is not a separate field list: it inherits whatever the
helper read surface already exposes, so every field added in Phases 5 through 7
needs auditing **once**, not twice, and there is no allowlist at `full` to
erode.

`progress` means **public only**: authored fields render if and only if
`isPublic`. It additionally hides the two things _nobody authored_ — helper
names and coach cards — because there is no moment at which their author could
have chosen to expose them.

| Field                                    | `progress` | `full` |
| ---------------------------------------- | ---------- | ------ |
| Root title + rolled-up percent           | yes        | yes    |
| Objective title, status, lifecycle badge | yes        | yes    |
| Weight in parent                         | yes        | yes    |
| Occurrence count + completion percent    | yes        | yes    |
| Per-day occurrence log                   | yes        | yes    |
| Detail text (public)                     | yes        | yes    |
| Detail text (**private**)                | **no**     | yes    |
| Clarifying answers (public)              | yes        | yes    |
| Clarifying answers (**private**)         | **no**     | yes    |
| Notes (public)                           | yes        | yes    |
| Notes (**private**)                      | **no**     | yes    |
| Helper name                              | **no**     | yes    |
| Coach cards                              | **no**     | yes    |
| Write access                             | none       | none   |

This is simpler than an allowlist per field: authored content is governed by one
rule (`isPublic`), and only two unauthorshipable fields need naming explicitly.
Phase 4 still uses **one serializer taking a visibility filter**, not two code
paths — but the filter has two inputs, not a growing table.

#### Item visibility flags

Notes, detail text and clarifying answers each carry an `isPublic` flag.

- **Default?** Public, unless the author says otherwise. Hiding-by-default would
  make every note a deliberate act of disclosure.
- **Who sets it:** the author, on their own items. The **owner may override**
  any item's flag. Nobody else may re-classify another's writing.
- **What `private` means:** hidden from `progress` observers, **visible at
  `full`**. It does not mean secret from the owner, who always sees everything.
- **Occurrence logs carry no flag.** Logging a walk is an act, not a statement.
  Flagging it would let a helper hide the evidence behind a block's own
  arithmetic, which is what observers are there to see.

#### Redaction — the denyList

Each observer has a **denyList** of objectives. A denied objective renders as
**redacted**: no title, no detail, no answers, no notes — but its **progress
still shows**, including its rolled-up percent and occurrence counts.

Redaction is the mirror image of a grant, and the two compose:

| Observer×objective             | Result                              |
| ------------------------------ | ----------------------------------- |
| Granted, not denied            | **Visible**, at the observer's tier |
| Not granted (grants non-empty) | Not shown at all                    |
| Granted, **denied**            | **Redacted** — progress, no title   |
| Empty grants, **denied**       | **Redacted** — progress, no title   |
| Empty grants, not denied       | **Visible** — the whole plan        |

Redaction is **not** absence. The observer knows work is happening and can see
how it is going, but not what it is — which is the point. "I want accountability
on this branch but it is about something I would rather not discuss" is a
reasonable thing for a helper to want, and this is the mechanism for it.

Three rules make it honest rather than leaky:

1. **Redaction cascades to the whole subtree.** A visible child reveals its
   redacted parent — the child title is nearly always a decomposition of it. So
   denying a node denies everything beneath it. This is worth noticing against
   the rule beside it: **grants do not inherit, but redaction does.** The
   asymmetry is deliberate. A grant says "you may see this", which should not
   quietly widen; a redaction says "you may not see this", which must not be
   circumventable by a child title.
2. **A redacted objective still counts in the parent rollup.** If it were
   excluded, the parent's percent would silently stop matching the sum of its
   visible children, and the observer could no longer reason about the plan at
   all. The numbers stay complete; only the labels are withheld.
3. **Redaction is labelled, never silent.** The observer is told something is
   withheld, not left to infer that an objective is empty. Stealth redaction
   would be the wrong call — it misleads the very person the plan is being
   accountable to.

**Authority.** A helper may redact objectives **inside their own subtree**;
the owner may redact anywhere. This mirrors the existing abandon-authority rule
exactly, so there is one subtree-permission concept in the app rather than two.

#### Why both grants and a denyList

They look redundant, and one of the two could be dropped. Keeping both is a
choice about what the _unset_ state should mean:

- **Grants only** means an owner must enumerate an observer's entire view
  before they see anything — verbose, and the empty case is awkward
  ("nothing granted" vs "everything granted" differ only in intent).
- **DenyList only** inverts the default to full visibility, with no
  safe-by-default state.
- **Both** lets the owner pick per observer: grant a branch, or open the whole
  plan and redact a few nodes from it. The composition is one subtraction, so
  the cost is a boolean per objective rather than a second model.

The redundancy is confined to _which objectives_; the tier and item flag handle
_what they contain_, so no mechanism is doing another's job.

### Observer grants

Grants are a **per-node allowlist with no subtree inheritance.** Granting an
objective does not expose its children — an owner who wants a branch visible
grants the nodes in it. Inheriting would mean granting one node silently opened
up whatever got added beneath it later, which is the opposite of what an
allowlist is for.

Grants pointing at a node that has since been re-parented or removed are
**silently ignored** rather than raising an error — a stale grant is not the
observer's problem to fix.

**Empty grants means "no restrictions", not "nothing".** An observer granted
nothing sees the **whole plan** at their tier. This is an explicit selection the
owner makes, not a default that falls out of forgetting to configure it.

That distinction has one edge worth naming in the UI: _grant the root only_ and
_grant nothing_ look identical until the tree has children. Granting the root
shows the root's percent and nothing beneath; granting nothing shows everything.
The participant management screen needs to make that difference explicit rather
than relying on the owner to infer it.

### Identity

One `participant` record per person per plan, keyed by `participantId`. Auth is
an _attribute_ of that record, not a precondition for it — which is what lets a
helper upgrade without orphaning their assignments or history.

- **Owner**: Microsoft account via Easy Auth.
- **Helper**: magic-link invite keyed by email. Claiming creates a participant
  with an email and no credential. They may later register an account, which
  **links to the same participant** rather than creating a second one.
- **Observer**: invited the same way, with a tier attached at claim time. Both
  the grant set and the denyList start **empty**, which means full visibility at
  their tier.

Invites are per-plan. The invite token carries `(planId, role, subtreeRootId |
null, visibilityTier | null)`. It carries **no display-mode field** —
light/dark/system is the reader's own, client-side, and never travels with an
invite. Grants and the denyList are **not** in the token either; both are
mutable state on the participant, changed after the claim, since a redaction a
helper adds next week should not require a fresh invite link.

---

## Lifecycle

Lifecycle and progress are **two orthogonal dimensions**, deliberately not
collapsed into one status field:

- **Lifecycle**: `draft` → `active` → `archived`, or `→ abandoned` from either.
  Applies to plans and to objectives.
- **Progress** (leaves only): `not started` / `in progress` / `blocked` / `done`.

What each lifecycle state does to rollup:

| State              | Rollup                | Notes                              |
| ------------------ | --------------------- | ---------------------------------- |
| `draft` / `active` | computes normally     | —                                  |
| `archived`         | keeps its percent     | tree freezes and becomes read-only |
| `abandoned`        | **excluded entirely** | renders as `abandoned`, no percent |

- Archiving is a plan-level move: the tree freezes and becomes read-only.
  Archived does not affect rollup.
- **Archiving never renews.** Bulk renewal is a separate explicit action taken
  beforehand. See _Renewal is independent of archiving_.
- Abandoning an objective removes it from the rollup but keeps its history and
  keeps it visible.
- A repeatable abandoned mid-block stops the recurrence; the partial log remains
  and renders on the renewed block.

---

## The AI coach

One agent, three jobs, **all writes staged for human approval**.

1. **Clarify** — before decomposing a vague objective, ask one to three
   questions. Answers are stored on the objective and ground later coaching.
2. **Decompose** — propose child objectives with suggested weights and suggested
   parent weights. Proposals land as `proposal` rows; the owner edits and
   accepts. Never auto-applied.
3. **Coach** — triggered by inactivity (a leaf `in progress` with no **write**
   for N days) or by a `blocked` status. Emits a dismissible `coachCard` on the
   objective suggesting a next step, a re-split, or a request for help.

Coach cards are **hidden from `progress` observers** — they are advice
addressed to a worker, not plan state. They carry no public/private flag: they
are generated, not authored, so there is no moment at which their author could
have chosen. See _Observer visibility tiers_.

**SMART checking is mostly not the AI's job.** `targetCount` and `endDate` are
required fields, so _measurable_ and _time-bound_ are structurally enforced. The
AI's clarify step only has to catch the soft dimensions — vague (_specific_),
unevidenced (_relevant_), implausible (_achievable_). A much smaller and cheaper
job, and it runs at every level of the tree rather than only at the root.

**Coaching a repeatable is opt-in per objective and heavily damped.** Missed
consecutive occurrences produces one card and then silence. A long zero-rate
window suggests lowering the target, which is the honest fix more often than
not. A recurring "you haven't walked yet" prompt is explicitly **rejected** — it
is the failure mode that gets these apps deleted. Coaching a `blocked` one-shot
objective remains the primary job and is unchanged.

**Unattended coaching is deferred.** In Phases 1-5 the coach runs on demand
("coach me", status changes, expand requests). Phase 6 adds a daily scheduled
sweep for stalled work using a Container Apps Job — the smallest thing that
provides it, chosen so the messaging stack stays closed.

---

## App experience

- **Declare an objective** → clarify → staged breakdown → accept → assign
  helpers.
- **Tree view**: expand/collapse, weighted percent per node, lifecycle badge,
  owner, assignee. Unassigned children visibly drag the parent's percent down.
  A childless node shows `—`, not `0%`.
- **Objective detail**: detail, clarifying answers, status, weight-in-parent
  (owner-editable only), **notes**, occurrences and
  completion rate for repeatables, coach cards, and for resolved blocks the
  verdict with the raw count. Detail text, clarifying answers and notes each
  carry a **public/private toggle at write time**, shown to
  the author and overridable by the owner.
- **Redacted node**: renders as _"redacted"_ with no title,
  no detail and no children — but keeps its rolled-up percent and occurrence
  counts, so the surrounding arithmetic still adds up. Labelled, never silent.
- **Observer management**: set an observer's tier, their
  **grants**, and their **denyList**. The grants control needs an explicit
  "no restrictions — sees the whole plan" option, distinct from "grant the root
  only", because the two render identically on an empty tree. Redaction shows a
  warning that it cascades to the whole subtree. A helper managing their own
  subtree sees the redaction control, scoped to their own work.
- **Observer preview**: view the plan through a given
  observer's eyes before inviting them. With three filters composing, guessing
  what someone will see is no longer safe.
- **Theming**: display mode (light / dark / system) as a
  per-user, client-side preference; the plan's colour theme and font-family set
  by the owner and applied to everyone who opens it.
- **Owner inbox**: approve/reject proposals — AI decompositions and upward edits
  from helpers.
- **Renewal**: per-objective renew, plus bulk renew. **Archive is a separate
  button**.
- **Participant management**: invite helpers and observers, set a helper's
  subtree, set an observer's visibility tier, grants and denyList.
- **Observer view**: renders what grants allow, minus the denyList, at the
  observer's tier. Redacted objectives show progress without a title.

---

## Repo layout (`~/repos/objective-oriented-planning`)

```plaintext
objective-oriented-planning/
  infra/        Bicep modules: rg, appconfig (shared), acr (shared),
                cosmos, keyvault, containerapps, monitor
  api/          FastAPI: objectives, tree, rollup, participants, invites,
                occurrences, notes, proposals, visibility, coach/
  web/          Frontend (Vite + React): tree, objective detail, owner inbox,
                participant management, renewal, observer view
  scripts/      deploy.sh, teardown.sh, common.sh, seed
  docs/         architecture.md, KQL queries, CI_TEARDOWN.md
```

Copy `teardown.sh`, `common.sh`, `deploy.sh`, and `deploy-shared.sh` from
`~/repos/memorywell/scripts/` rather than designing cost control from scratch,
and review them against the current versions before copying — they were written
for memorywell's Phase 1.

---

## Build phases

Phase-based, **strictly sequential, one brief at a time, no skipping ahead and
no pre-implementation of later phases.** Build mode is **learning-first**: the
human implements by hand; the agent's output is the brief, not the
implementation.

**Phase execution contract (applies to every phase):**

1. Agent writes a phase brief: goal, concepts, prerequisites, instructional
   steps in order, file outline (paths + stubs, not implementations), manual
   verification checks, and what to demo before proceeding.
2. Human builds it by hand following the brief (agent answers questions and
   unblocks, but does not take over).
3. Brief closes with a review gate: what to show or paste back so the agent can
   sanity-check before the next brief is issued.

| #   | Phase                     | Contents                                                                                                                                                                                                                                                                                       |
| --- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Foundation                | Bicep: resource group, shared RG, ACR, App Configuration, Key Vault, Log Analytics; skeleton API on Container Apps (min replicas 0, revisions day one); repo scaffold **with `pre-commit` + `.editorconfig` in the first commit**; `teardown.sh` + nightly CI teardown workflow with pre-check |
| 2   | Data + core API           | Cosmos DB serverless (single container, `planId` partition key), domain types including `timezone` / tier / grant / `isPublic` fields, weighted rollup and block scoring as **pure, unit-tested functions**, `_etag`-checked write path                                                        |
| 3   | Identity + invites        | Magic-link claim, Easy Auth owner sign-in, participants, helper subtree assignment, observer grants / denyLists / tiers, per-plan invites                                                                                                                                                      |
| 4   | Tree UI + permissions     | Tree view, status edits, subtree enforcement server-side, owner proposal inbox, participant management, observer preview; **notes entity and the UI that renders them**                                                                                                                        |
| 5   | Coach agent               | Clarify → staged decompose with weight proposals → on-demand coaching cards; SMART soft checks; **stale-approval presented as a review step**; config via `config.py` + App Configuration                                                                                                      |
| 6   | Unattended coaching       | Daily Container Apps Job sweeping stalled and blocked leaves; repeatable coaching (damped, opt-in); decide here whether App Configuration should drive thresholds                                                                                                                              |
| 7   | Observability + hardening | OpenTelemetry end-to-end, KQL workbook, alerting on job failures, teardown verification hardening                                                                                                                                                                                              |

**Build starts at Phase 1**, full plan, sequential.

---

## Cost & safety

Cheapest viable tier of every service, per the house rule:

| Resource          | Tier                            | Always-on cost                                                                  |
| ----------------- | ------------------------------- | ------------------------------------------------------------------------------- |
| Cosmos DB         | Serverless                      | ~$0 idle, pay-per-RU                                                            |
| Container Apps    | Consumption, `minReplicas: 0`   | ~$0 idle                                                                        |
| App Configuration | Free tier, **one shared store** | $0                                                                              |
| Key Vault         | Standard, 1 vault               | ~$0.36/month                                                                    |
| ACR               | Basic                           | ~$5/month                                                                       |
| Log Analytics     | Pay-per-GB                      | **~$0 idle** — ingest-billed, and nothing flows while the app is scaled to zero |

**Estimated ~$5-6/month** while running, near **$0 with the environment torn
down**. ACR Basic and the vault are the entire recurring cost, which is
precisely why the ACR is shared rather than per-environment.

Cost controls:

- **Teardown story exists from Phase 1**, not a later cleanup phase. Everything
  for an environment in `rg-oop-<env>`; teardown is one `az group delete`.
- `rg-oop-shared` holds ACR and App Configuration so rebuilds do not re-push
  all images or re-create config.
- **Order matters**: delete the environment RG first, then the shared one.
  Reversed, a running container app can try to pull images mid-teardown.
- **Destructive scope is explicit and opt-in**: environment RG by default,
  `--shared` also drops the shared RG. `--purge-vault` is opt-in because RG
  deletion is async and the vault may not be soft-deleted yet.
- **CI teardown is nightly and permanent.** It stays in the repo permanently —
  it is cost-control infrastructure, not a development convenience. Nightly runs
  pass `--purge-vault` and verify afterwards; local runs make purge opt-in.
- **Cheap pre-check first**: if `rg-oop-<env>` does not exist and no vault is
  soft-deleted, report and skip every destructive step. `concurrency` per
  environment with `cancel-in-progress: false` so two teardowns cannot race.
- Auth with **OIDC** (`azure/login` + `id-token: write`), never a stored client
  secret; credential scoped to a GitHub `environment`.
- Because `.env` is git-ignored, CI injects `BASE_NAME` / `LOCATION` /
  `ENVIRONMENT` via repo variables and `AZURE_SUBSCRIPTION_ID` via secrets.
- Secrets never committed; managed identities plus Key Vault references.

---

## Verification

- `pytest` on the pure functions, which is where the correctness risk actually
  lives:
  - Rollup: single-child, unequal weights, unassigned child at 0%, abandoned
    children excluded from **both** numerator and denominator, empty-children
    parent returning `null`
  - Block scoring: target met, partial at the 50% boundary, missed, excess
    capped at 100%, today treated as pending not failed, day boundary computed
    in the plan's timezone not UTC
  - Renewal: history links to the prior block and is not copied; renewing is
    independent of archiving
  - Lifecycle: transitions and what each does to rollup, including that an
    abandoned plan yields no percent and an archived one keeps it
- Permission tests: helper can edit inside subtree, cannot above it, cannot
  write a child's weight; owner-only weight writes enforced server-side
- Observer tests:
  - a `progress` observer sees titles, status, weights, per-day occurrence logs
    and percents
  - a `progress` observer sees **no** helper names and **no** coach cards
  - a `progress` observer sees **public** detail, answers and notes but **not
    private** ones
  - a `full` observer sees everything a helper sees — including **private**
    items — and can write nothing
  - an observer with an **empty denyList sees the whole plan** at their tier
- Grant tests:
  - an observer granted the root only sees the root and nothing beneath
  - a grant does **not** inherit to children
  - an observer with an **empty grant set sees the whole plan** — distinct from
    granting the root, and asserted separately so the two cannot be confused
  - a grant pointing at a removed or re-parented node is ignored, not an error
- Redaction tests:
  - a redacted objective shows **no title** and **no detail**, but **does** show
    its rolled-up percent and occurrence counts
  - a redacted objective is **labelled redacted** — never rendered as empty
  - redaction **cascades**: redacting a node hides all its descendants
  - a redacted objective **still counts in its parent's rollup**; excluding it
    would break the arithmetic
  - a helper may redact **only within their own subtree**; attempting it outside
    is rejected server-side
  - the owner may redact anywhere
  - redaction is per-observer: two observers, two denyLists, one unredacted
  - re-adding an objective to the tree does **not** resurrect it if a
    descendant was still denied — redaction is resolved against the current tree
- Composition tests: the full truth table
  - granted + not denied → visible
  - **not granted** (grants non-empty) → not shown, even at `full`
  - granted + denied → **redacted**
  - empty grants + denied → **redacted**
  - empty grants + not denied → visible
- Item visibility flag tests:
  - author sets `isPublic` on their own note, detail or answer; it defaults to
    public
  - the **owner may override** any item's flag; another helper may not
  - flipping a note to private removes it from a `progress` observer's view and
    **leaves it visible at `full`**
  - occurrence logs have **no** flag and are visible to both tiers
  - a flag change is itself an `_etag`-checked write and resets the inactivity
    clock
- Concurrency: two writes to the same objective with the
  same `_etag` — the second returns `409`; a write with a fresh `_etag` succeeds
- Stale approval: a proposal raised against `_etag` N,
  approved after the objective moved to `_etag` N+1 — the owner is **shown the
  differences** and can still approve; no `409` surfaces as an error, and the
  proposal is neither lost nor silently applied
- Timezone: changing the plan's zone affects a new block's
  day boundaries and does **not** change an already-resolved block's verdict; an
  invalid zone is rejected at write time
- Cache: a write response's percent reflects the write, not
  a cached read; a read within the TTL may be stale, a read after it is not
- AI: clarify fires on a vague objective and not on a SMART one; decompose
  always stages; coach card appears on a stalled leaf and on a `blocked` leaf;
  **any write** to a stalled leaf suppresses the card;
  repeatable coach produces **one** card, then silence
- Manual per-phase: send request → see the entity in Cosmos → see traces in Log
  Analytics → empty error path
- End-to-end: declare a vague objective → clarify → accept breakdown → assign
  helper → helper updates a leaf → parent percent moves → helper proposes an
  upward edit → owner approves → parent percent moves again → block resolves as
  partial → renew → prior block shown as history

---

## Design notes

Design reasoning that is not obvious from the sections above. Earlier versions
of this plan are kept as `PLAN.v1.md`.

### Why observer visibility has three filters

It looks redundant, and one of the three could be dropped. The reason it is not
is the **empty state**.

- **Grants only** — an owner must enumerate an observer's entire view before
  they see anything. Verbose, and "nothing granted" vs "everything granted"
  differ only in intent.
- **DenyList only** — inverts the default to full visibility, leaving no
  safe-by-default state.
- **Both** — the owner chooses per observer: grant a branch, or open the whole
  plan and redact a few nodes from it.

The redundancy is confined to _which objectives_. The tier and the item flag
handle _what those objectives contain_, so no mechanism is doing another's job,
and the composition is one subtraction rather than a second model.

One asymmetry inside this is deliberate and will otherwise look like a bug:
**grants do not inherit to children, but redaction does.** A grant says "you may
see this" and should not quietly widen; a redaction says "you may not see this"
and must not be circumventable by a child title.

### Why archiving does not renew

Archiving freezes the tree; renewal mutates it. Bundling them means the owner
cannot archive without also deciding to renew every in-flight block. They are
two deliberate steps instead of one ambiguous one.

### Why redaction keeps counting in the rollup

Because an observer watching a plan needs the arithmetic to hold. Excluding a
redacted objective would leave the parent's percent silently disagreeing with
the sum of its visible children. The numbers stay complete; only the labels are
withheld — which is what makes redaction a privacy control rather than a way to
make a plan look better than it is.

### Why notes are a Phase 4 deliverable

Notes are a first-class entity but land with the UI that renders them, not with
the Phase 2 data model. The cost is that between Phases 3 and 4 the observer
tier is stored and enforced but filters nothing observable, since notes are the
only field it hides. That is acceptable in a sequential build where each phase
demos its own slice.

### Why stale approvals are a review step

A `409` is correct for an ordinary edit and wrong for approving a proposal. The
owner has already made a considered decision; showing them an error is a dead
end with no meaningful retry. So any flow where a user has decided something
surfaces the conflict as a review step, never as a failure. Approving a proposal
is the first such flow; Phase 5 may find others.

### Deliberately deferred — post-MVP

Wanted, but explicitly **after** the MVP rather than during it. Recorded here so
they are not lost and not smuggled into an earlier phase:

- **Push notifications / email** — telling helpers a proposal was raised, a
  coach card appeared, or a block resolved. Today everything is pull-based,
  which is fine for a plan checked deliberately. Communication Services has a
  free tier, and the seams (an inbox, a coach card, a resolved verdict) are
  already in the model.
- **Audit log** — who changed what, and who approved it. Most valuable exactly
  where staged proposals are approved. Append-only rows in the same container
  are trivial; a UI for them is not.
- **Plan export on archive** — a JSON dump of the tree and its occurrences.
  Roughly thirty lines, and it pairs naturally with archiving.
- **Observer summary email** — a periodic "how the plan went" digest. Arguably
  the thing that makes granting observer access worth granting at all. Depends
  on the notifications seam above.

None of these is a regression; the original plan never promised them, and each
would have added a phase.

### Open question, deliberately undecided

There is no default tier for an observer invited without one specified. That
should be decided when Phase 3 builds participant management, where the choice
is concrete and visible — not here, where it would be a guess.

### Phase 2 scope, if it needs splitting

Phase 2 is trimmed back to domain types, the timezone / tier / grant fields, and
the etag-aware write path. If it still proves too much for a single brief, the
natural split is **domain types + fields** as 2a and **pure rollup/scoring
functions + the etag-aware write path** as 2b. Either order works — unlike the
notes split, there is no field here that is meaningless without the others.

### Theming

Two separate things, deliberately not one setting:

**Display mode — light / dark / system — belongs to the reader.** It is a
per-user preference, held client-side (`localStorage` is sufficient), and **is
not stored server-side**. No participant field, no invite token field, nothing
persisted. The default is `system`, resolving from `prefers-color-scheme`, so a
visitor who has expressed no preference gets the one their OS already asks for.

Keeping it client-side means it costs nothing, survives the plan being
abandoned, and adds nothing to the data model. The only cost is that a helper
who reads on two devices sets it twice — which is correct behaviour for a
reading preference, not a defect.

**Plan aesthetics — colour theme and font-family — belong to the plan.** This
is the owner expressing what the plan looks like to everyone who opens it, and
it _is_ stored server-side on the plan, because it is a shared property rather
than a personal one.

The distinction matters for observers: an observer sees the plan's colour and
font, but keeps their own display mode. A `progress` observer who prefers dark
still gets dark.

Theming lands in **Phase 4**, with the first UI, and not in Phase 1. Theming
applied after a UI exists means reworking every style declaration, which is the
same retrofitting problem the `pre-commit` rule exists to avoid — so the point is
that it is decided _before_ the tree UI is written, not that it is built before
the UI exists. Phase 1 records the choice; Phase 4 implements it.

**The choice: CSS custom properties, no component library.** Plan aesthetics are
data on the plan (`colourTheme`, `fontFamily`), so they have to be resolved at
runtime onto whatever the styles read. Custom properties are the cheapest way to
express "a value the owner set, applied to everything", and a component library
would work against that by baking colours into components at build time. A
library remains worth revisiting if the tree view turns into something a
hand-rolled component set cannot carry — but the bar is set by theming, not by
comfort.
