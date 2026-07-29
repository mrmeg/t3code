# T3 Connect: How the Pieces Fit (mrmeg self-host)

Companion to [SELFHOST.md](./SELFHOST.md) (setup checklist). This explains the
running system: what each piece is, how traffic flows, and where to look when
something breaks.

## The cast

| Piece           | What it is                                                                                                                                                         | Where it lives                                  |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------- |
| **Relay**       | Cloudflare Worker `t3coderelay-api-prod-*` serving `https://relay.mrmeg.com`. The rendezvous point: clients find environments through it; it never runs your code. | Mrmegenhardt Cloudflare account, mrmeg.com zone |
| **Relay DB**    | Postgres storing users, environment links, device push tokens. Reached from the Worker via Hyperdrive.                                                             | `Postgres` service, Railway `devbox` project    |
| **Clerk**       | Identity. One Clerk app (`clerk.code.mrmeg.com`) signs in every surface: phone, web, desktop, CLI.                                                                 | clerk.com                                       |
| **Environment** | A machine running `t3 serve` — the actual T3 server with your repos, terminals, agents. You have two: the Mac and the Railway devbox.                              | Your hardware / Railway                         |
| **Tunnel**      | A managed `cloudflared` process each environment runs. Outbound-only connection from the environment to Cloudflare's edge, so no ports are ever opened inbound.    | Spawned by `t3 serve`                           |
| **Clients**     | The iOS app (`com.mrmeg.code`), web, desktop. They talk to the relay, never directly to an environment's IP.                                                       | Your phone etc.                                 |

## How a request flows

1. Phone signs into Clerk, mints a JWT from the `t3-relay` template
   (audience `t3-code-relay`).
2. Phone calls `relay.mrmeg.com` with that JWT. The relay validates it and
   looks up your linked environments in Postgres.
3. To reach an environment, traffic goes phone → Cloudflare edge → down the
   cloudflared tunnel that environment's `t3 serve` holds open → local
   `t3 serve` on 127.0.0.1.

So: the relay is the phonebook + switchboard; the tunnel is the wire; Clerk is
the ID check at both ends. An environment with no running `t3 serve` has no
tunnel and shows unreachable — that's expected, not broken.

## Auth flows (two different ones)

- **Clients (phone/web/desktop):** normal Clerk sign-in, JWT per request.
- **CLI (`t3 connect ...`):** OAuth PKCE against Clerk's public OAuth app.
  The browser callback lands on `127.0.0.1:34338`, so on a headless box you
  must forward that port first: `ssh -L 34338:127.0.0.1:34338 railway-devbox`.
  The credential is stored per **data directory** — the devbox serve uses
  `--base-dir /data/t3code`, so connect commands there need
  `--base-dir /data/t3code` too, or you'll authorize the wrong store.

## Where configuration lives

| Location                           | Contents                                                                                                                                  | Consumed by                                                                                                            |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| repo `.env` / `.env.local`         | Public client values: `T3CODE_RELAY_URL`, `T3CODE_CLERK_PUBLISHABLE_KEY`, `T3CODE_CLERK_JWT_TEMPLATE`, `T3CODE_CLERK_CLI_OAUTH_CLIENT_ID` | Baked into mobile/web/desktop builds at build time; read at runtime by source-built CLI                                |
| Railway `devbox` service variables | The same four `T3CODE_*` values                                                                                                           | The devbox's `t3 serve` (published npm package bakes in the _official_ relay, so these runtime overrides are required) |
| `infra/relay/.env`                 | Deploy-time secrets: Clerk secret key, APNs key, `RELAY_DATABASE_URL`, zone names                                                         | `vp run --filter t3code-relay deploy` (Alchemy)                                                                        |

Key consequence: changing a public value means **rebuilding** the mobile app
(`vp run ios:release`) but only **restarting** the devbox (vars are runtime
there).

## Lifecycle facts worth knowing

- `t3 connect login` = stores a CLI credential. `t3 connect link` = records
  durable "expose this environment" intent. Neither starts anything — the next
  `t3 serve` startup reconciles the link and launches the tunnel.
- The devbox's `t3 serve` is started by the container entrypoint. To restart
  it: `railway redeploy --service devbox`. Link/credential state lives on the
  `/data` volume and survives redeploys.
- On the Mac, run `t3 serve` from `apps/server` (`node dist/bin.mjs serve`),
  or install the background service (`t3 service install`) so it survives
  reboots.

## Debugging map

| Symptom                                | Look at                                                                                                                                                                                                                                                                    |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Environment missing/unreachable in app | `t3 connect status` on that machine (devbox: add `--base-dir /data/t3code`). "pending server startup" = restart serve.                                                                                                                                                     |
| Devbox serve behavior                  | `/tmp/t3.log` on the devbox (search `reconcil`, `tunnel`, `Registered`)                                                                                                                                                                                                    |
| Relay API errors                       | Cloudflare Workers observability for `t3coderelay-api-prod-*`; Axiom datasets                                                                                                                                                                                              |
| 403 with `cf-mitigated: challenge`     | Cloudflare zone security challenged a non-browser client. Bot Fight Mode and Browser Integrity Check on mrmeg.com must stay **off** (Free plan can't scope exceptions; that needs Pro + WAF skip rules). Datacenter IPs (Railway) trip this; residential ones often don't. |
| Push notifications                     | Relay uses CF Queues (Workers Paid) + APNs key from `infra/relay/.env`                                                                                                                                                                                                     |

## Upstream sync

`sync-fork` skill handles it. Diverged relay files are listed in
[SELFHOST.md](./SELFHOST.md#upstream-sync-notes) — re-check `src/db.ts`
(Railway Hyperdrive origin) after any upstream rebase, then re-run
`pnpm migrate:railway` if the schema moved.
