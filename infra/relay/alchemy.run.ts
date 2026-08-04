// @effect-diagnostics anyUnknownInErrorContext:off layerMergeAllWithDependencies:off - Alchemy provider helpers expose framework-owned any requirements.
import * as Alchemy from "alchemy";
import * as Axiom from "alchemy/Axiom";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Drizzle from "alchemy/Drizzle";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Option from "effect/Option";

import * as RelayDb from "./src/db.ts";
import { RelayObservability } from "./src/observability.ts";
import { WebApp } from "./src/webApp.ts";
import { ManagedEndpointZone, RelayApiZone } from "./src/zone.ts";
import ApiLive, { Api } from "./src/worker.ts";

export default Alchemy.Stack(
  "T3CodeRelay",
  {
    providers: Layer.mergeAll(Axiom.providers(), Cloudflare.providers(), Drizzle.providers()),
    state: Cloudflare.state(),
  },
  Effect.gen(function* () {
    const hyperdrive = yield* RelayDb.RelayHyperdrive;
    const managedEndpointZone = yield* ManagedEndpointZone.pipe(Effect.orDie);
    const relayApiZone = yield* RelayApiZone.pipe(Effect.orDie);
    const observability = yield* RelayObservability;
    const api = yield* Api;
    const webApp = yield* WebApp.pipe(Effect.orDie);

    return {
      hyperdriveName: hyperdrive.name,
      workerName: api.workerName,
      url: api.url,
      webAppUrl: Option.match(webApp, {
        onNone: () => "",
        onSome: ({ domain }) => `https://${domain}`,
      }),
      relayApiZoneId: relayApiZone.zoneId,
      managedEndpointZoneId: managedEndpointZone.zoneId,
      mobileTracingUrl: observability.traces.otelTracesEndpoint,
      mobileTracingDataset: observability.traces.name,
      mobileTracingToken: observability.mobileIngestToken.token,
      clientTracingUrl: observability.traces.otelTracesEndpoint,
      clientTracingDataset: observability.traces.name,
      clientTracingToken: observability.clientIngestToken.token,
    };
  }).pipe(Effect.provide(ApiLive)),
);
