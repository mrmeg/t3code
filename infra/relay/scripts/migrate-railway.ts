#!/usr/bin/env node
// @effect-diagnostics nodeBuiltinImport:off globalConsole:off - standalone Node script, not Effect code.
// Personal fork: apply migrations/postgres to the Railway relay database.
// Upstream applies migrations through Alchemy's PlanetScale resources; this
// fork's database is plain Railway Postgres, so migrations run out-of-band:
//
//   RELAY_DATABASE_URL=postgresql://... node scripts/migrate-railway.ts
//
// Reads RELAY_DATABASE_URL from the environment or infra/relay/.env. Uses the
// same migrations table ("relay_migrations") and row shape as the upstream
// runner so a future move back to managed migrations stays compatible.
import { createHash } from "node:crypto";
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import pg from "pg";

const relayDir = dirname(dirname(fileURLToPath(import.meta.url)));
const migrationsDir = join(relayDir, "migrations", "postgres");
const MIGRATIONS_TABLE = "relay_migrations";

function loadDatabaseUrl(): string {
  if (process.env.RELAY_DATABASE_URL) return process.env.RELAY_DATABASE_URL;
  const envFile = join(relayDir, ".env");
  if (existsSync(envFile)) {
    for (const line of readFileSync(envFile, "utf8").split("\n")) {
      const match = line.match(/^\s*RELAY_DATABASE_URL\s*=\s*(.+?)\s*$/);
      if (match?.[1]) return match[1].replace(/^["']|["']$/g, "");
    }
  }
  throw new Error("RELAY_DATABASE_URL is not set (env or infra/relay/.env).");
}

const migrations = readdirSync(migrationsDir, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name)
  .sort()
  .map((name) => ({
    id: name,
    sql: readFileSync(join(migrationsDir, name, "migration.sql"), "utf8"),
  }));

const client = new pg.Client({ connectionString: loadDatabaseUrl() });
await client.connect();

try {
  await client.query(
    `CREATE TABLE IF NOT EXISTS "${MIGRATIONS_TABLE}" (
       id TEXT PRIMARY KEY,
       name TEXT NOT NULL,
       applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
     );`,
  );

  const appliedRows = await client.query<{ id: string; name: string }>(
    `SELECT id, name FROM "${MIGRATIONS_TABLE}";`,
  );
  const applied = new Set(appliedRows.rows.map((row) => row.name));
  let nextSeq =
    appliedRows.rows
      .map((row) => (/^\d+$/.test(row.id) ? Number.parseInt(row.id, 10) : 0))
      .reduce((max, n) => Math.max(max, n), 0) + 1;

  for (const migration of migrations) {
    if (applied.has(migration.id)) {
      console.log(`skip  ${migration.id}`);
      continue;
    }
    const migrationId = String(nextSeq++).padStart(5, "0");
    await client.query("BEGIN");
    try {
      // Drizzle emits multiple statements separated by this marker.
      for (const statement of migration.sql.split("--> statement-breakpoint")) {
        const sql = statement.trim();
        if (sql) await client.query(sql);
      }
      await client.query(`INSERT INTO "${MIGRATIONS_TABLE}" (id, name) VALUES ($1, $2);`, [
        migrationId,
        migration.id,
      ]);
      await client.query("COMMIT");
      console.log(`apply ${migration.id}`);
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    }
  }
  console.log(`done (${migrations.length} migrations tracked)`);
} finally {
  await client.end();
}
