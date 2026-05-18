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

## Object storage (Quickwit + ClickHouse)

ClickHouse and Quickwit have very different stories on GCS:

- **ClickHouse** has no native GCS backend. It must go through GCS's S3 interoperability layer with HMAC keys, configured via typed `clickhouse.s3.accessKeyId` / `accessKeyIdFrom` rendered into `storage_config.xml`. `useEnvironmentCredentials: true` does NOT work on GKE because the GKE metadata server returns OAuth2 tokens, which GCS's S3 API does not accept.
- **Quickwit 0.8.2** does have a native GCS backend (the `quickwit/quickwit:v0.8.2` Docker image is built with `release-feature-set`, which enables `quickwit-storage/gcs`). Native path: set `quickwit.s3.defaultIndexRootUri: "gs://bucket/..."`, optionally `quickwit.gcs.credentialPath` for a mounted SA JSON, and Quickwit's reqsign-based credential loader runs the standard chain: credential_path → `GOOGLE_APPLICATION_CREDENTIALS` → `~/.config/gcloud/application_default_credentials.json` → GKE metadata server. **GKE Workload Identity works out of the box** on the native path — bind the GCP SA, annotate the K8s SA, done.

Quickwit URI schemes the v0.8 binary parses: `s3://`, `gs://`, `azure://`, `file://` (also `ram://`, `actor://`, `grpc://`, `postgresql://` for non-storage uses). The current public docs list `gs://` but the v0.8.2 markdown in the repo doesn't — trust the source and the runtime, not the markdown.

The chart's `quickwit.s3.flavor: gcs` + `endpoint: https://storage.googleapis.com` path is the **HMAC-keys-on-S3-API fallback**, kept for parity with ClickHouse-on-GCS and for environments without Workload Identity. Always recommend the native `gs://` path first.

When adding new Quickwit storage knobs, render them into `quickwit-configmap.yaml` only. The configmap is mounted at `/quickwit/node.yaml` via `subPath`, which the kubelet does not live-update; every Quickwit workload template carries `checksum/config` in its pod annotations so a `helm upgrade` that edits the configmap forces a rolling restart.

## Per-component knobs

For services with multiple workloads (Quickwit, ClickHouse), expose `extraEnv` both at the parent level and at each component. The parent-level value covers the common case (cloud-wide credentials); the per-component value is for overrides like indexer-only tuning. Use `concat` in the helper so duplicates fall through Kubernetes' "later wins" semantics on the env array.
