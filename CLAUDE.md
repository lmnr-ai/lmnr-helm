# CLAUDE.md — lmnr-helm

Helm charts shipped to Laminar self-host customers. The chart in `charts/laminar/` is the user-facing artifact; `laminar.yaml` is the minimal-config example operators copy and edit.

## Layout

- `charts/laminar/values.yaml` — full default values, with inline comments serving as the user-facing reference.
- `charts/laminar/templates/` — one file per Kubernetes resource. Quickwit is split across five workloads (control-plane, indexer, janitor, metastore, searcher) that share a single ConfigMap (`quickwit-configmap.yaml`) and a single ServiceAccount.
- `examples/` — opinionated overlays operators apply on top of `laminar.yaml`. Each example is referenced from `examples/README.md`.
- `CONFIGURATION.md`, `QUICKSTART.md`, `NETWORKING.md`, `DEPENDENCIES.md` — long-form docs. CONFIGURATION.md is the authoritative reference; new chart features must be linked from its TOC.

## Verification before opening a PR

Render with both AWS and an alternate (GCS / non-AWS) values file and parse the output as YAML. Helm renders successfully even when the result is malformed:

```bash
helm lint charts/laminar -f laminar.yaml
helm template test charts/laminar -f laminar.yaml > /tmp/render.yaml
python3 -c "import yaml; list(yaml.safe_load_all(open('/tmp/render.yaml')))"
```

A common failure mode: two `toYaml` blocks emitted back-to-back into a `env:` array merge their last and first entries onto a single line. Use `concat` in helpers that combine two lists, then a single `toYaml`.

## Quickwit gating

The whole Quickwit stack (workloads + `QUICKWIT_*_URL` env vars on the three app pods) is gated on the `lmnr.quickwit.enabled` helper, which returns true only when BOTH `quickwit.enabled: true` AND `quickwit.s3.defaultIndexRootUri` is non-empty. The bucket gate is the important one: Quickwit pins each index's storage URI in the metastore at index-creation time, so the frontend's first-boot `initializeQuickwitIndexes` against a placeholder bucket will permanently bake the wrong URI in — later overriding `defaultIndexRootUri` does not relocate existing indexes (LAM-1649). Default is empty string; operators MUST point it at their bucket to enable Quickwit. When adding a new resource that depends on Quickwit, gate it with `{{- if include "lmnr.quickwit.enabled" . }}`, not `{{- if .Values.quickwit.enabled }}` — the latter would let the resource render against a placeholder bucket.

## Derived secrets in secrets.yaml

`secrets.yaml` auto-generates a few values when the operator hasn't set them and they aren't sourced from an external store (AWS Secrets Manager / Vault). The guard pattern is always: `not <key in $awsKeys/$vaultKeys>` plus `not .Values.secrets.data.<KEY>` for the target, then emit. `DATABASE_URL`/`CLICKHOUSE_URL`/`RABBITMQ_URL` follow this; so does `SLACK_ENCRYPTION_KEY`, which defaults to `AEAD_SECRET_KEY` (instance uses one at-rest key, not two). When adding a derived secret, check the target key isn't already in `secrets.data` so an explicit operator value wins and isn't emitted twice into the same Secret `data:` map.

## Slack integration (self-hosters)

Self-hosters use the brokered OAuth flow via `secrets.data`: `SLACK_BROKER_URL` (= `https://laminar.sh`, Laminar Cloud's origin) + `LMNR_LICENSE_KEY`. This uses Laminar Cloud's official Slack app, so self-hosters don't recreate the Slack app or set `SLACK_CLIENT_ID`/`SECRET`/`SIGNING_SECRET`/`REDIRECT_URL` (those were removed from the chart — bring-your-own is no longer supported). `LMNR_LICENSE_KEY` is the general enterprise license key (reused by other paid features), authenticated broker-side via SHA3-256 hash lookup against the Cloud `slack_broker_instances` table. Documented under "Slack Integration" in CONFIGURATION.md.

## Object storage (Quickwit + ClickHouse)

The chart configures both Quickwit and ClickHouse on GCS through GCS's S3 interoperability layer using HMAC keys, so the auth model is identical across the two services. Configuration is parallel but not identical:

- **ClickHouse** has no native GCS backend, so HMAC-via-S3 is the only option. Typed `clickhouse.s3.accessKeyId` / `accessKeyIdFrom` rendered into `storage_config.xml`. The `useEnvironmentCredentials: true` path does not work on GKE because the GKE metadata server returns OAuth2 tokens, which GCS's S3 API does not accept.
- **Quickwit 0.8.2 *does* have a native GCS backend** (the `quickwit/quickwit:v0.8.2` image is built with `release-feature-set`, which enables `quickwit-storage/gcs`), and the v0.8 binary's reqsign-based credential loader will pick up GKE Workload Identity tokens out of the box. We deliberately don't expose that path in the chart today — keeping Quickwit on the same HMAC-via-S3-API model as ClickHouse means operators configure one set of credentials, not two. If a customer asks for the native `gs://` + Workload Identity path, see git log around LAM-1618 for the implementation that was reverted; bringing it back is mechanical.
- **Quickwit auth shape**: no typed credential fields; HMAC keys come in as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` env vars via `quickwit.extraEnv` (chart-wide) or `quickwit.<component>.extraEnv` (per-pod). The configmap exposes `s3.flavor` and `s3.endpoint` for non-AWS stores; when either is left empty the chart auto-fills based on `global.cloudProvider` (`gcp` → `flavor: "gcs"` + `endpoint: "https://storage.googleapis.com"`; `aws` → emits nothing, AWS SDK defaults apply). Explicit values always win, so MinIO/R2/etc. still work.

When adding new Quickwit storage knobs, render them into `quickwit-configmap.yaml` only. The configmap is mounted at `/quickwit/node.yaml` via `subPath`, which the kubelet does not live-update; every Quickwit workload template carries `checksum/config` in its pod annotations so a `helm upgrade` that edits the configmap forces a rolling restart.

## Per-component knobs

For services with multiple workloads (Quickwit, ClickHouse), expose `extraEnv` both at the parent level and at each component. The parent-level value covers the common case (cloud-wide credentials); the per-component value is for overrides like indexer-only tuning. Use `concat` in the helper so duplicates fall through Kubernetes' "later wins" semantics on the env array.

## Postgres schema

`global.postgresSchema` (default `"public"`) is dispatched as `POSTGRES_SCHEMA` into all three app pods (app-server, app-server-consumer, frontend) so they share one `search_path` — it MUST be a single global, never per-pod, since the services would silently diverge otherwise. `POSTGRES_CREATE_SCHEMA` (`frontend.env.postgresCreateSchema`) is frontend-only because only the frontend runs migrations / `CREATE SCHEMA` on boot. A `public` value (any case) is the default schema: never created, migrations stay in the standard `drizzle` tracker. Documented under "Postgres Schema" in CONFIGURATION.md.
