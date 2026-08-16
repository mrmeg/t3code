#!/usr/bin/env node

// The StaticSite build executor tokenizes `command` into argv without a
// shell, so the two build steps cannot be chained with `&&` there.
import { execFileSync } from "node:child_process";

execFileSync("vp", ["run", "--filter", "@t3tools/web", "build"], {
  stdio: "inherit",
});
execFileSync("node", ["scripts/apply-web-brand-assets.ts", "production"], {
  stdio: "inherit",
});
