import * as NodePath from "node:path";
import * as NodeURL from "node:url";

import * as Cloudflare from "alchemy/Cloudflare";
import * as Config from "effect/Config";
import * as Effect from "effect/Effect";
import * as Option from "effect/Option";

import { RelayDeploymentConfig } from "./zone.ts";

const REPO_ROOT = NodePath.resolve(
  NodePath.dirname(NodeURL.fileURLToPath(import.meta.url)),
  "../../..",
);

/**
 * Hosted web client (mrmeg self-host): builds apps/web with the relay's
 * public config baked in and serves it as Worker static assets on
 * WEB_APP_DOMAIN (e.g. code.mrmeg.com). The web build reads the Clerk +
 * relay public values from the repo-root .env via loadRepoEnv; only the
 * hosted-app origin is injected here so isHostedStaticApp() activates.
 *
 * Only provisioned when WEB_APP_DOMAIN is set, so upstream stages without
 * it are unaffected.
 */
export const WebApp = Effect.gen(function* () {
  const { stage } = yield* RelayDeploymentConfig;
  const webAppDomain = yield* Config.string("WEB_APP_DOMAIN").pipe(
    Config.option,
    Config.map(
      Option.flatMap((value) => {
        const trimmed = value.trim();
        return trimmed ? Option.some(trimmed) : Option.none();
      }),
    ),
  );

  if (Option.isNone(webAppDomain)) {
    return Option.none();
  }

  const site = yield* Cloudflare.Website.StaticSite("WebApp", {
    cwd: REPO_ROOT,
    // The executor spawns argv without a shell (`shell: true` is accepted by
    // the type but not honored), so the two build steps live in a wrapper.
    command: "node scripts/build-hosted-webapp.ts",
    outdir: "apps/web/dist",
    env: {
      VITE_HOSTED_APP_URL: `https://${webAppDomain.value}`,
      // Skip .map emission: halves the asset upload and nothing consumes
      // them on the hosted origin.
      T3CODE_WEB_SOURCEMAP: "false",
    },
    memo: {
      include: ["apps/web/**", "packages/**", "scripts/**", ".env", ".env.local", "pnpm-lock.yaml"],
      exclude: ["**/node_modules/**", "**/dist/**"],
    },
    assets: {
      notFoundHandling: "single-page-application",
    },
    domain: webAppDomain.value,
  });

  return Option.some({ site, domain: webAppDomain.value, stage });
});
