# Personal Relay Deployment (mrmeg)

This fork runs its own T3 Connect relay: `relay.mrmeg.com`, backed by the Railway
Postgres in the devbox project instead of PlanetScale. Reference:
[docs/cloud/t3-connect-clerk.md](../../docs/cloud/t3-connect-clerk.md).

## One-time account setup (manual)

1. **Cloudflare — Workers Paid** (required for Queues used by APNs delivery):
   Dashboard > mrmegenhardt account > Workers & Pages > Plans > upgrade to Workers Paid ($5/mo).
2. **Clerk** — create an application (clerk.com), then:
   - JWT template named `t3-relay` with claims `{ "aud": "t3-code-relay" }`.
   - OAuth application for the CLI: Public (PKCE), redirect `http://127.0.0.1:34338/callback`,
     scopes `openid profile email`. Note the client ID.
   - Native applications: enable Native API, add an iOS app with Team ID `WRC5RMB343`
     and bundle ID `com.mrmeg.code`.
   - Copy publishable + secret keys into `infra/relay/.env`
     (`CLERK_PUBLISHABLE_KEY`, `CLERK_SECRET_KEY`).
3. **Axiom** — sign up (free tier), create an API token with dataset-management rights,
   and authenticate the Alchemy Axiom provider (it will prompt on first deploy).
4. **Apple Developer** — Certificates, Identifiers & Profiles > Keys > create an APNs key.
   Also enable Push Notifications on the `com.mrmeg.code` App ID. Fill `APNS_KEY_ID` and
   `APNS_PRIVATE_KEY` (the .p8 contents) in `infra/relay/.env`.

## Database

The relay database is the `Postgres` service in the Railway `devbox` project.
`RELAY_DATABASE_URL` in `infra/relay/.env` is its public TCP proxy URL. Migrations
do not run on deploy; apply them after pulling upstream schema changes:

```sh
cd infra/relay
pnpm migrate:railway
```

## Deploy

```sh
vp run --filter t3code-relay deploy -- --stage prod
```

On success the wrapper writes `T3CODE_RELAY_URL` into the repo-root `.env`.

## After deploy

1. Repo-root `.env` additions (publishable key, template name, OAuth client ID —
   public values, fine to keep in the committed personal env if desired):
   ```dotenv
   T3CODE_CLERK_PUBLISHABLE_KEY=pk_...
   T3CODE_CLERK_JWT_TEMPLATE=t3-relay
   T3CODE_CLERK_CLI_OAUTH_CLIENT_ID=client_...
   T3CODE_RELAY_URL=https://relay.mrmeg.com
   ```
2. Rebuild mobile from source (`vp run ios:release`) so the cloud UI is compiled in.
3. Devbox: the published npm package bakes in the official relay; override at runtime
   instead. Set the same four `T3CODE_*` variables in the environment that launches
   `t3 serve` on the devbox.
4. On the devbox: `t3 connect login` then `t3 connect link` (forward the OAuth
   callback port first: `ssh -L 34338:127.0.0.1:34338 railway-devbox`).

## Upstream sync notes

Diverged files: `src/db.ts`, `alchemy.run.ts`, `package.json` (pg deps + script),
plus this file and `scripts/migrate-railway.ts` (new, conflict-free). If upstream
changes `src/db.ts`, re-apply the Railway Hyperdrive origin on rebase.
