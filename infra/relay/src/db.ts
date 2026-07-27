import type { PgClient } from "@effect/sql-pg/PgClient";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Drizzle from "alchemy/Drizzle";
import type { EffectPgDatabase } from "drizzle-orm/effect-postgres";
import * as Config from "effect/Config";
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Redacted from "effect/Redacted";

export class RelayDb extends Context.Service<
  RelayDb,
  EffectPgDatabase & {
    readonly $client: PgClient;
  }
>()("t3code-relay/db/RelayDb") {}

export class RelayTransactions extends Context.Service<
  RelayTransactions,
  {
    readonly withTransaction: RelayDb["Service"]["$client"]["withTransaction"];
  }
>()("t3code-relay/db/RelayTransactions") {
  static readonly layer = Layer.effect(
    RelayTransactions,
    Effect.gen(function* () {
      const db = yield* RelayDb;
      return RelayTransactions.of({
        withTransaction: db.$client.withTransaction,
      });
    }),
  );
}

export const RelaySchema = Drizzle.Schema("RelaySchema", {
  schema: "./src/persistence/schema.ts",
  out: "./migrations/postgres",
  dialect: "postgres",
});

// Personal fork: the relay database is a Railway Postgres instance instead of
// PlanetScale. RELAY_DATABASE_URL must be the Railway public TCP proxy URL
// (postgresql://user:pass@host.proxy.rlwy.net:port/railway) so Hyperdrive can
// reach it. Migrations are applied out-of-band by scripts/migrate-railway.ts,
// not by the deploy.
export const RelayHyperdrive = Effect.gen(function* () {
  yield* RelaySchema;
  const databaseUrl = yield* Config.nonEmptyString("RELAY_DATABASE_URL");
  const url = new URL(databaseUrl);
  return yield* Cloudflare.Hyperdrive.Connection("RelayHyperdrive", {
    origin: {
      scheme: "postgres",
      host: url.hostname,
      port: url.port ? Number(url.port) : 5432,
      database: url.pathname.replace(/^\//, ""),
      user: decodeURIComponent(url.username),
      password: Redacted.make(decodeURIComponent(url.password)),
    },
    caching: {
      disabled: true,
    },
    originConnectionLimit: 20,
  });
});
