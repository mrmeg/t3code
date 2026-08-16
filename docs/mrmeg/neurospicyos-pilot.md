# NeurospicyOS Pilot — Managed T3 Code Environment

Master plan for giving the NeurospicyOS client a zero-install T3 Code setup (browser +
phone only), with an AI Triforce quality process, running as a real-world test of this
fork's infrastructure. Fork-specific: lives alongside `infra/relay/SELFHOST.md` and
`infra/relay/HOW-IT-WORKS.md`, which document the infra this plan builds on.

## What we're building

A dedicated, always-on T3 Code environment for the client, hosted on Railway, that they
reach through the fork's hosted web client (code.mrmeg.com) and a fork-built mobile app —
with nothing installed on their computer. All identities on the environment are theirs
(GitHub, Claude, Clerk), so the setup is portable and privilege separation comes from
ownership, not roles. Development quality is governed by a Triforce skill flow (Infinite
Red's Builder / Protector / Organizer model) committed to their app repo, enforced by
GitHub branch protection rather than prompt obedience.

## Why this benefits the client

- **Zero setup, work from anywhere.** Browser or phone; no Node, no CLI, no local state.
  Their environment is always on — no "my laptop was closed" gaps.
- **Velocity without debt.** The Triforce flow means every AI change arrives as a PR with
  an agenda report (what changed, why it works, risks), gets an independent
  test/security/accessibility review pass, and can't merge without approval. They get the
  speed of agentic development with an auditable quality gate.
- **Ownership and portability.** Their GitHub account authors the commits, their Claude
  credential runs the agent, their repo carries the skills and guardrails. If the pilot
  ends, everything they care about moves with them — the devbox is replaceable.
- **Visibility.** Progress is legible as PRs, agenda reports, and Organizer debt reports —
  not a chat log. They always know what state their app is in.

## Architecture and ownership map

| Component       | What                                                                                                   | Owner / identity                                                  | Pays            |
| --------------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------- | --------------- |
| Devbox          | Railway service, published `t3` npm pkg, `t3 serve --base-dir /data/t3code`, persistent `/data` volume | Matt-managed, **separate Railway project** from Matt's own devbox | Matt            |
| GitHub          | Client's app repo + `gh auth login` on devbox                                                          | Client                                                            | —               |
| Model provider  | Claude credential on devbox (API key or `claude setup-token`)                                          | Client (or Matt-provisioned key with spend cap — decide)          | Client / decide |
| Relay           | relay.mrmeg.com (control plane only; brokers Cloudflare tunnel, never runs code)                       | Matt (multi-tenant; client is 2nd tenant)                         | Matt            |
| Web client      | code.mrmeg.com (static, baked with fork Clerk + relay values via `infra/relay/src/webApp.ts`)          | Matt                                                              | Matt            |
| Cloud account   | Clerk user on fork's Clerk instance (allowlisted email)                                                | Client                                                            | Matt (Clerk)    |
| Mobile app      | Fork build, `production:device` EAS profile, relay URL baked to relay.mrmeg.com                        | Matt builds, client's device                                      | Matt            |
| Triforce skills | `.agents/skills/` + `.claude/skills` symlink, committed to client repo                                 | Client repo (Matt authors)                                        | —               |

Traffic: web/mobile → Clerk sign-in → relay looks up environment → direct connection over
the devbox's outbound `cloudflared` tunnel. The relay never sees code or repo contents.

## Workstreams

### WS1 — Devbox provisioning

1. New Railway project (isolated from Matt's own devbox — the agent gets a shell in this
   container). Service runs published `t3` package; volume mounted at `/data`;
   `t3 serve --base-dir /data/t3code` as entrypoint; the four `T3CODE_*` public vars as
   service variables (runtime override of the baked official relay).
2. Over `railway ssh`: `gh auth login` as the **client's** GitHub account; clone their app
   repo under `/data`; install the client's Claude credential.
3. `t3 connect login` (forward port 34338 over SSH for the loopback OAuth flow, per
   SELFHOST.md) signed in as the **client's** Clerk user, then
   `t3 connect link --base-dir /data/t3code`.
4. Check Cloudflare Bot Fight Mode exclusion for Railway egress IPs early
   (known 403 `cf-mitigated: challenge` failure — HOW-IT-WORKS.md).

**Done when:** the environment shows linked and reachable for the client's Clerk user, and
survives a `railway redeploy` (state on `/data`).

### WS2 — Web access

1. Allowlist the client's email on the fork's Clerk instance (or enable restricted mode).
2. Client signs into code.mrmeg.com, sees their devbox environment, opens the project,
   runs a trivial agent turn end-to-end.

**Done when:** client completes an agent turn from their own browser with no local install.

### WS3 — Mobile

The App Store build cannot be used: relay URL + Clerk keys are baked at build time
(`apps/mobile/app.config.ts:363`, no runtime override), so it only reaches relay.t3.codes /
upstream Clerk — environments linked to relay.mrmeg.com never appear. (Fallback only:
the store build's direct-pairing mode can reach the devbox via a `t3 pair` URL against the
tunnel hostname, but loses push/Live Activities and the environment list — break-glass, not
the plan.)

1. Collect client device UDID; register in the Apple provisioning profile.
2. Build from fork with `production:device` profile (added in `702c44701`; internal
   distribution, no auto-increment). Mirror repo `.env` `T3CODE_*` values into the EAS
   environment — fingerprint diverges otherwise (known gotcha).
3. Deliver via EAS internal-distribution install link; client signs into the same Clerk
   account; environment appears.
4. Updates: ad-hoc installs don't auto-update. JS-level changes ship OTA via EAS Update on
   the fork's own Expo project id + pinned channel (`1892ca38b`); native changes need a
   rebuild + new install link. If client count grows past ~2, switch to TestFlight under a
   fork bundle id (`T3CODE_IOS_BUNDLE_ID`).

**Done when:** client runs an agent turn from the phone over the relay-managed connection.

### WS4 — Triforce skill flow (in the client's app repo)

1. `.agents/skills/{triforce-build,triforce-protect,triforce-organize}/SKILL.md` +
   committed `.claude/skills → ../.agents/skills` symlink (house style: numbered imperative
   steps, enumerated failure branches, cross-skill routing, `agents/openai.yaml` sidecars).
   - `$triforce-build` (Builder/PXA): take a ticket, read `GUARDRAILS.md` first, implement
     within its boundaries, open a **draft PR with an agenda report** (what changed, why it
     works, risks, what was NOT verified). Never merges.
   - `$triforce-protect` (Protector/IE): consume agenda report + diff; run the
     test/security/accessibility checklist; approve or write back a blocking findings list.
     Human clicks merge.
   - `$triforce-organize` (Organizer/SE): periodic debt/architecture-drift report; owns and
     updates `GUARDRAILS.md` (locked areas, patterns, must-nots).
2. `GUARDRAILS.md` seeded with the app's initial constraints.
3. Committed `.claude/settings.json`: deny `Bash(gh pr merge*)` and other hard "must nots"
   (T3 passes `settingSources: ["user","project","local"]`, so the spawned Claude Code
   honors these).
4. GitHub branch protection on main: require PR review, no direct pushes. This is the only
   _hard_ merge gate — the skills are process, branch protection is enforcement.
5. Client threads default to supervised / auto-accept-edits, not full-access (T3's
   per-thread default is full-access; set expectations in onboarding).

**Done when:** skills appear in the `$` picker as Project scope; a `$triforce-build` run
produces a draft PR that cannot merge without review; `$triforce-protect` produces a
findings list on a seeded defect.

### WS5 — Client onboarding

1. One-pager for the client: how to sign in (web + phone), the three skills and when to use
   each, what a good ticket looks like, what to do when the Protector blocks a PR.
2. Live walkthrough: one full Triforce cycle on a real small ticket.

**Done when:** client completes a build → protect → merge cycle without help.

## Inputs needed from the client (collect before WS1)

- GitHub repo access + which account authors on the devbox
- Claude credential decision (their subscription token vs. Matt-provisioned capped API key)
- Email for the Clerk allowlist
- iPhone UDID
- Their top 3 "must never happen" items for `GUARDRAILS.md`

## Risks and mitigations

- **Pairing links are bearer credentials** (terminal access; 5-min single-use). Prefer the
  Clerk/relay path for the client; if a pairing link is ever needed, send over a secure
  channel and revoke stale devices after.
- **Full-access default mode** — onboarding sets supervised/auto-accept-edits as the norm.
- **Devbox blast radius** — isolated Railway project; only client credentials on the box;
  nothing of Matt's reachable from it.
- **Bot Fight Mode 403s** — verify exclusion during WS1, not during the client demo.
- **Relay quota** — 3 managed tunnels per user by default; fine for one devbox, override
  exists if needed.
- **Cost** — devbox + tunnel + Clerk on Matt; Claude usage should be on a client credential
  or a capped key so agent spend is bounded and attributable.

## What this pilot tests for the fork

- relay.mrmeg.com with a second real tenant (Clerk multi-tenancy, allowlist flow, quota)
- code.mrmeg.com hosted web client in third-party hands
- `production:device` fork mobile build lifecycle (UDID, EAS env mirroring, install, OTA-less updates)
- Feature gaps to watch for as fork candidates:
  1. **Scoped pairing links** (read-only / no-terminal) — delegated-pairing route already
     accepts scope subsets; no CLI/UI exposes it. The real "limited privileges" gap.
  2. **Per-project default permission mode** (full-access default is wrong for clients).
  3. **Role pinning per thread** (a thread that stays in one Triforce role).

## Sequencing

WS1 → WS2 can happen as soon as client inputs arrive (one sitting). WS3 is independent
after UDID arrives. WS4 can be drafted in parallel today (skills + guardrails template),
landing in their repo whenever access is granted. WS5 last. No workstream blocks another
except WS5 needing all of WS2–WS4.
