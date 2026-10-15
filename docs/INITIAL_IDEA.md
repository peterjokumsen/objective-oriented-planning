# Objective-Oriented Planning — Idea Brief

An application where a person declares a single objective, and AI helps them
prepare the steps needed to achieve it. Those steps are themselves objectives,
so the plan is a tree rather than a flat list. Other people can be brought in as
**helpers** (assigned child objectives they own) or **observers** (progress
visibility with limited view of the actual details).

## The shape of it

One plan = one declared objective. Inside it, a recursive tree of child
objectives. Progress rolls up: the root shows the weighted completion of its
children, whose weighted completion comes from theirs, down to leaf objectives
that a helper actually works on.

Helpers can be assigned a subtree and edit freely inside it. Anything above
their assignment is read-only, except that they may **propose** edits for the
owner to approve. Observers see the plan read-only, filtered by grants, a
per-observer list of redacted objectives, and a visibility tier.

## What the AI is for

Not a one-shot "break this down" button. A coaching agent with three jobs:

1. **Clarify** — vague objectives ("get fitter") get one to three questions
   asked before anything else happens. Answers are stored on the objective and
   ground everything that follows.
2. **Decompose** — propose child objectives with suggested weights. Proposals
   are staged, never auto-applied; the owner edits and accepts.
3. **Coach** — when a leaf sits `in progress` with no update for a while, or is
   `blocked`, suggest a next step, a re-split, or a request for help. Arrives
   as a dismissible card on the objective.

Coaching is on-demand at first. Unattended coaching (a scheduled sweep for
stalled work) is deliberately deferred until the core tree is solid.

## SMART objectives

Every objective is SMART, so nothing runs forever. A repeatable is a **bounded
block** rather than an open-ended habit:

> Walk 5 minutes a day, 5 days per week, from 3 Nov to 13 Dec.

Cadences: `daily`, `weekdays`, `n-per-week`, `monthly`. When a block's end date
passes it is scored from its log → **successful**, **partial** (≥ 50%), or
**missed**. A block can then be **renewed** into a fresh block that carries the
prior history forward for display — that is how a habit continues without any
objective being infinite.

Measurability and time-bounding are enforced by required fields rather than by
the AI, so the AI only has to catch the soft parts (vague, unevidenced,
unbelievable).

## Roles

- **Owner** — creates the plan, assigns helpers, sets weights, approves upward
  edits, grants observers visibility. Real account (Microsoft sign-in).
- **Helper** — owns an assigned subtree, may abandon objectives in it, may
  propose edits upward. Magic-link invite by default; can register a real
  account later and keep their assignments and history.
- **Observer** — read-only. Sees what grants allow, minus anything redacted.
  `progress` shows only public content; `full` sees everything a helper sees.
  Redacted objectives keep their progress but lose their title and details.

## Non-goals for now

- Multi-tenant workspaces with independent owners (one plan, one owner).
- Unattended / scheduled coaching.
- Rich numeric estimation — weights are an owner-declared relative judgement,
  not points or story points.

Wanted after the MVP: push notifications, an audit log, plan export, and a
periodic observer summary.
