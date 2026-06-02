# Pyramid Analytics → SNC K8s (snowsk8s) Deployment Plan

> **Status:** Planning / for review · **Author:** initial analysis via Claude Code · **Date:** 2026-06-02
> **Audience:** SNC platform + app engineers / agents picking up the implementation.
>
> **Golden rulebook:** `~/code/snc/k8s/docs-snc` (snowsk8s platform docs) — 📘 below.
> **Reference implementation:** `~/code/snc/k8s/datalake` (a live Heimdall v4 GitOps workload) — 📦 below.
>
> This document is the **what/how/why**. It does not yet contain the implemented repo; see "Execution" at the end.

---

## 1. What this chart is

This repo is the **public Pyramid Analytics Helm chart** (a GitHub-Pages Helm repo: `Chart.yaml` + `index.yaml` + `packages/*.tgz` + `artifacthub-repo.yml`). It is a **standalone chart with zero Helm sub-chart dependencies** (no `dependencies:` block; all in-tree templates).

- **Chart:** `pyramidanalytics` v`2025.10.005`, `apiVersion: v2`, `type: application`.
- The working tree **is** the chart source; `packages/pyramidanalytics-2025.10.005.tgz` is just the packaged artifact (no need to unpack).

### Services deployed (8 Deployments)

| Service | Template | Image (`{{repo}}/…`) | Role | Scaling (default off) |
|---|---|---|---|---|
| ws (web) | `ws_deployment.yaml` | `ws` | HTTP/auth front end, port **8181** | KEDA (Prometheus) |
| rtr (router) | `rtr_deployment.yaml` | `rtr` | request routing core | static |
| rte (runtime) | `rte_deployment.yaml` | `rte` | query/CMS engine + satellites | HPA |
| te (task) | `te_deployment.yaml` | `te` | ETL/print engine + satellites/printers | KEDA |
| ai | `ai_deployment.yaml` | `ai` | Python/R scripting | HPA |
| nlp | `nlp_deployment.yaml` | `nlp` | chatbot/NLP engine | HPA |
| solve | `solve_deployment.yaml` | `solve` | solver engine | HPA |
| gis | `gis.yaml` | `gis` | geospatial (toggle, 1 replica) | none |

### Supporting resources
- `service.yaml` — a **`LoadBalancer`** Service `pyramid` (→ ws:8181) + ClusterIP `pyramid-ws-metrics` (Prometheus scrape :9090, `/metricsfull`).
- `role.yaml` — namespaced RBAC: `pa-service` & `installer-service` SAs; Roles (pods get/list/create/delete/patch, services CRUD, secrets get/update, PVC list, leases get/update).
- `prometheus.yaml` — a **bundled Prometheus** incl. **ClusterRole/ClusterRoleBinding** (to be removed; see G3).
- `te_lease.yaml` — coordination Lease for TE master election.
- `unattended.yaml` — Secret carrying full install config (DB creds, admin password, license) when `unattended.enabled`.
- `persistentVolumeNfs.yaml` / `persistentVolumeGoogleStore.yaml` — NFS PV / GKE Filestore CSI (to be removed; see G4).
- `*_hpa.yaml` — KEDA `ScaledObject`s / HPAs (all default **off**).

### External dependencies (must exist outside the chart)
1. **SQL database** — Postgres or SQL Server. Not deployed by the chart.
2. **Repository/file store** — PersistentVolume **or** external object storage (S3 / Azure Blob / FTP / SFTP / NFS).
3. **KEDA + metrics-server** — only if autoscaling is enabled.
4. **Container images** from Docker Hub `pyramidanalytics/*` (+ `prom/prometheus`).

### Security posture (good news)
Pod security contexts are already platform-compliant: `runAsNonRoot: true`, `runAsUser: 1001` (gis 1000, prometheus 65534), `allowPrivilegeEscalation: false`, **no** privileged / hostPath / hostNetwork / hostPort.

---

## 2. SNC platform deployment model (verified against docs-snc)

Deployment is **NOT** `helm install` / `kubectl apply`. It is **GitOps via Heimdall + CMDB + Heimdall-CI image sync**:

- **Heimdall** (`brew install --cask heimdall`) scaffolds a project (Helm chart + env overlays + `heimdall.yaml`); an in-cluster **Heimdall controller** reconciles the Git repo → `helm upgrade --install`. Config layers: chart defaults → overlays → CMDB. **Heimdall creates the namespace — you must not** ship a `Namespace` resource or hard-code `namespace:`. 📘 `build-and-deploy/deployment-model.md`, `quick-start.md`
- **CMDB** (datacenterdev.service-now.com): register **Workload → Workload Family (= git branch) → Workload Instance (= cluster, state `Published`)**, plus Service Templates and Storage Instances. 📘 `cmdb/`
- **Glitnir** = admission policies that reject non-compliant manifests. 📘 `glitnir/`
- **One workload per namespace.** Inter-workload comms only via ADC (external LB), not cluster DNS. 📘 `deployment-model.md`

> ⚠️ **Correction to an earlier draft:** image promotion uses **Heimdall CI** (`heimdall ci` in GitLab CI), **not Bifrost**. Confirmed by `datalake/.gitlab-ci.yml`.

---

## 3. Gap analysis — chart vs. snowsk8s policy

| # | Chart today | snowsk8s requires | Severity |
|---|---|---|---|
| **G1** | Images from Docker Hub (`pyramidanalytics/*`, `prom/prometheus`) | `deny-untrusted-registries`: images must match `*.artifactory.servicenow.net/*`. **Sync** 8 images via Heimdall CI → set `repo` to `docker-local.artifactory.servicenow.net/...` in snc overlay. 📘 `glitnir/controls/deny-untrusted-registries.md` | 🔴 Blocker |
| **G2** | `LoadBalancer` service with **no annotations** | `id.loadbalancer.access` rejects LBs without a CMDB Service Instance. Add `ccm.snowsk8s.servicenow.net/{lb-service-id, lb-service-ip-space, lb-healthcheck-http-path, lb-healthcheck-http-status-code-regex}`. 📘 `ingress/_index.md`, `ingress/health-checks.md` | 🔴 Blocker |
| **G3** | Bundled Prometheus incl. ClusterRole/ClusterRoleBinding | Platform provides observability (scrape from `radium`). Cluster-scoped RBAC disallowed for workload teams. **Remove `prometheus.yaml`**; keep `pyramid-ws-metrics` annotations. 📘 `observability/_index.md` | 🟠 High |
| **G4** | NFS PV / GKE Filestore | `storage-class` policy: only **`titanium`** allowed (NFS/`manual`/GKE rejected). **AND** titanium is block/CSI = **RWO**, but Pyramid mounts `/opt/pyramid-repo` **RWX** across ws/te/rte/ai/nlp/solve → titanium cannot back it. **Use object storage (OaaS S3)** for the repo instead. 📘 `glitnir/access/storage-class.md`, `storage/block-storage.md` | 🟠 High |
| **G5** | `unattended.yaml` holds plaintext DB/admin/license (+ S3 keys) in values | Secrets via **DCPS + External Secrets Operator**, never committed to git. 📘 `secrets/_index.md` | 🟠 High |
| **G6** | No NetworkPolicies | Default deny-all. Add CiliumNetworkPolicies: DNS egress, intra-app mesh, ADC→ws ingress, DB/S3 egress, `radium`→metrics ingress. 📘 `network-policies/_index.md` | 🟠 High |
| **G7** | `namespace: {{ .Release.Namespace }}` | Acceptable; ship **no** `Namespace` resource; verify one-workload-per-ns. 📘 `deployment-model.md` | 🟡 Medium |
| **G8** | DB external, not in chart | Provision DB reachable from cluster; creds via DCPS. (Recommend in-cluster Postgres StatefulSet on titanium RWO.) | 🟡 Medium |
| **G9** | KEDA/HPA (off) | Confirm KEDA + metrics-server cluster-provided before enabling. Leave **off** for v1. | 🟢 Low |

---

## 4. Two non-obvious architecture decisions (READ THIS)

1. **Repository store = object storage (OaaS S3), NOT a PersistentVolume.**
   Pyramid mounts `/opt/pyramid-repo` as **ReadWriteMany** across `ws/te/rte/ai/nlp/solve`. The only platform storage class, `titanium`, is **block/CSI = ReadWriteOnce** → it cannot back a shared RWX mount. `datalake` hit the same wall and uses OaaS S3 (`dvb402.oaas.servicenowlab.com`). → Set Pyramid `storageType: AWSS3`, `storage.type: other` (no PVC).
2. **Database = in-cluster PostgreSQL StatefulSet on titanium (RWO, single pod)** — copy `datalake/charts/postgresql`. RWO is fine for a single writer. (Managed DB is the alternative.)

---

## 5. Image sync mechanism (Heimdall CI) — how datalake does it

**Three Artifactory registries** (`datalake/.gitlab-ci.yml`):

| Var | Registry | Purpose |
|---|---|---|
| `DOCKER_REGISTRY` | `docker-remote.artifactory.servicenow.net` | Docker Hub pull-through proxy (sync **source**) |
| `GITLAB_REGISTRY` | `docker-gitlab-remote.artifactory.servicenow.net` | gitlab registry proxy |
| `CI_REGISTRY` / `ARTIFACTORY_DOCKER_REGISTRY` | `docker-local.artifactory.servicenow.net` | local/push repo (**destination**, matches trusted allowlist) |

Destination path = `docker-local.artifactory.servicenow.net/gitlab.servicenow.net/${CI_PROJECT_NAMESPACE}/${CI_PROJECT_NAME}/<upstream-repo-path>`.

**Jobs** (gated behind a `sync_images` pipeline input, default false):
- `heimdall-ci-generator` runs `heimdall ci …` → inspects rendered charts, finds upstream images, **generates a child `pipeline.yml`** that pulls from the proxy → pushes to `docker-local` → scans.
- `heimdall-ci-tasks` triggers that generated pipeline.
- Auth: service account `svc-snowsk8s_apps_<project>` + `$KEEPER_TOKEN`, `--with-tokenkeeper-token-refresh-job`, `.tokenkeeper.yaml` (`repositories: [docker-local]`).
- `heimdall.yaml` declares: `ci.sync_images: [{id: snc-from-ci, environment: ci, skipRegistries: [artifactory.servicenow.net]}]`.

**"Use the images" pattern (upstream in base, Artifactory in `snc` overlay):**
- Base `values.yaml` references public images (works for `heimdall kind`).
- `overlays/<release>/snc/values.yaml[.gotmpl]` overrides the same key to `docker-local.artifactory.servicenow.net/...`.
- Custom-built images (datalake's `etl-service`, `spark`) point at `docker-local` even in base, built by GoldenEye `build-container` (kaniko) jobs. **Pyramid builds nothing → drop all kaniko jobs, keep only the sync.**

---

## 6. End-to-end task plan

Each task cites the 📘 docs-snc rule and the 📦 datalake reference file.

### Phase 0 — Prerequisites & decisions
- **0.1** Install Heimdall (`brew install --cask heimdall`); ensure `helm-diff` (`export HELM_PLUGINS="$(heimdall home)/plugins"`). 📘 `quick-start.md`
- **0.2** Lock decisions: S3-for-repo + in-cluster Postgres; namespace `snowsk8s-pyramid`; autoscaling off; drop Prometheus.
- **0.3** Request OaaS S3 bucket + DCPS credential entries.
- **0.4** Create downstream repo `gitlab.servicenow.net/snowsk8s/apps/pyramidanalytics`.

### Phase 1 — Scaffold the Heimdall project
- **1.1** `heimdall create pyramidanalytics`.
- **1.2** `.heimdall-sites.yaml`: `version: v1` / `sites: {pyramidanalytics: {path: workload}}`. 📦 `datalake/.heimdall-sites.yaml`
- **1.3** `workload/heimdall.yaml`: `version: v4`, `name: pyramidanalytics`, `common_namespace: &ns snowsk8s-pyramid`, `environments: {local, snc, ci}` (snc overlays `[snc, cmdb]`), one `releases:` entry per chart with `after:` deps, `ci.sync_images` block. 📦 `datalake/workload/heimdall.yaml`

**Release dependency chain:**
```
namespace-creation (local only)
  └─ shared-resources            # CA bundle, DCPS SecretStore, NetworkPolicies, RBAC
       ├─ postgresql             # in-cluster DB (titanium RWO)
       └─ pyramid                # the 8 Pyramid services (after: [postgresql])
```

### Phase 2 — Adapt the Pyramid chart (`workload/charts/pyramid/`)
- **2.1** Security contexts already compliant; add `capabilities: {drop: [ALL]}`. 📘 `deny-container-run-as-root` · 📦 `spark`/`postgresql` overlays
- **2.2** Remove `templates/prometheus.yaml`; keep `pyramid-ws-metrics`. 📘 `observability/_index.md` (G3)
- **2.3** Remove `persistentVolumeNfs.yaml` + `persistentVolumeGoogleStore.yaml`; `storage.type: other`. 📘 `glitnir/access/storage-class.md` (G4)
- **2.4** Add CCM LB annotations to the `pyramid` service **in the snc overlay**. 📘 `ingress/health-checks.md` · 📦 `overlays/spark/snc/values.yaml.gotmpl` (G2)
- **2.5** Namespace hygiene: no `Namespace` resource. 📘 `deployment-model.md` (G7)
- **2.6** ⚠️ Adapt `unattended.yaml` to source DB/admin/license/S3 keys from the ExternalSecret-populated Secret instead of inline values — **validate against Pyramid's unattended JSON contract**. 📘 `secrets/_index.md` (G5)

**LB annotation block (snc overlay):**
```yaml
# overlays/pyramid/snc/values.yaml.gotmpl
service:
  annotations:
    ccm.snowsk8s.servicenow.net/lb-service-id: {{ "{{ .Values | get \"heimdall.workload.services.pyramid-web.id\" \"unknown\" }}" }}
    ccm.snowsk8s.servicenow.net/lb-service-ip-space: private
    ccm.snowsk8s.servicenow.net/lb-healthcheck-http-path: /
    ccm.snowsk8s.servicenow.net/lb-healthcheck-http-status-code-regex: "^200$"
```

### Phase 3 — Image sync (Heimdall CI) & tokens
- **3.1** Keep upstream images in base (`repo: pyramidanalytics`). 📦 base `config.yaml`
- **3.2** snc overlay sets `repo: docker-local.artifactory.servicenow.net/gitlab.servicenow.net/snowsk8s/apps/pyramidanalytics/pyramidanalytics` (verify resolved path after first sync). 📦 `overlays/postgresql/snc/values.yaml`
- **3.3** `heimdall.yaml` `ci.sync_images` block. 📦 `datalake/workload/heimdall.yaml`
- **3.4** `.gitlab-ci.yml`: copy datalake's `heimdall-ci-generator` + `heimdall-ci-tasks`; **drop all kaniko `build-container` jobs**; `CI_REGISTRY_USER: svc-snowsk8s_apps_pyramidanalytics`, `$KEEPER_TOKEN`. Gate on `sync_images`.
- **3.5** `.tokenkeeper.yaml`: `repositories: [docker-local]`; provision the service account + Keeper token. 📦 `datalake/.tokenkeeper.yaml`
- **3.6** Run pipeline with `sync_images: true` to populate Artifactory + vuln-scan **before** deploy. 📘 `vulnerability-management.md`

### Phase 4 — Secrets via DCPS (External Secrets Operator)
- **4.1** Create DCPS creds (lab `https://snccredentiallab.service-now.com`): `pyramid-db-credentials`, `pyramid-admin-credentials`, `pyramid-license`, `pyramid-s3-credentials`; API key → k8s secret `pyramid-dcps-apikey`.
- **4.2** `shared-resources` defines webhook `SecretStore` `pyramid-dcps`. 📦 `charts/shared-resources/templates/dcps/dcps-secret-store.yaml`
- **4.3** One `ExternalSecret` per cred (`secretStoreRef: {name: pyramid-dcps}`, `remoteRef.key` = DCPS cred name, `.result | fromJson` templating). 📦 `charts/postgresql/external-secret.yaml`, `charts/spark/external-secret.yaml`
- **4.4** Wire those Secrets into Pyramid unattended (Task 2.6).

### Phase 5 — Storage & Database
- **5.1** PostgreSQL chart on `titanium` RWO, single replica, `runAsUser 999 / drop ALL`. 📦 `charts/postgresql`
- **5.2** CMDB Storage Instance; PVC annotation `csi.snowsk8s.servicenow.com/storage_instance_id`; `cmdb` overlay templates `instanceId`. 📦 `overlays/postgresql/cmdb/values.yaml.gotmpl`, `overlays/postgresql/snc/values.yaml`
- **5.3** Pyramid repo on S3: `storageType: AWSS3`, `regionId`/`awsBucket`/keys from `pyramid-s3-credentials` ExternalSecret; OaaS S3 endpoint.

### Phase 6 — Networking, LB & CA bundle
- **6.1** ADC ingress CiliumNetworkPolicy (`fromEntities: [world, cluster]` → ws:8181). 📦 `networkpolicy-adcv2.yaml`
- **6.2** Intra-app mesh policy (ws↔rtr↔rte↔te↔ai↔nlp↔solve↔gis), `app.kubernetes.io/instance` selectors.
- **6.3** Egress: DNS→kube-dns:53; DB→postgresql:5432; S3→OaaS FQDN:443 (`toFQDNs`); `kube-apiserver` for API-reading pods. 📦 `networkpolicy-s3-egress.yaml`
- **6.4** Metrics ingress: `radium` → `pyramid-ws-metrics:9090`. 📘 `observability/_index.md`
- **6.5** CA bundle: `dcps/ca-bundle-snc.crt` → Secret, mount `/etc/ssl/snca`. 📦 `ca-bundle-secret.yaml`
- **6.6** CMDB Service Template yielding `pyramid-web.id`. 📘 `ingress/load-balancer-provisioning.md`

### Phase 7 — CMDB registration
- **7.1** Register Workload + Family (= branch) + Instance (cluster, state **Published**). 📘 `cmdb/`
- **7.2** `stubs/snc/workload-definition.yaml`: `heimdall.workload.{id, repo, services}` incl. `pyramid-web` service id + dns. 📦 `datalake/workload/stubs/snc/workload-definition.yaml`
- **7.3** `stubs/snc/menu.yaml`: `clusterName`/`clusterDC`. 📦 same
- **7.4** Link Postgres Storage Instance to the Workload Instance.

### Phase 8 — Local validation (kind)
- **8.1** `cd workload && heimdall client kind --environment=local`
- **8.2** `heimdall client apply --environment=local` (upstream images).
- **8.3** `helm template` each release; lint vs. glitnir control list.
- **8.4** Verify Pyramid reaches ready vs. local Postgres + S3; unattended/first-load completes.

### Phase 9 — Deploy to SNC + progressive rollout
- **9.1** Merge to `main`; run sync pipeline (`sync_images: true`).
- **9.2** `heimdall apply --environment=snc` to canary lab; verify LB provisions, pods ready, metrics scraped.
- **9.3** Promote: `release/sncsubprod-ca0 → ca1 → ca2 → sncsubprod`, then `release/sncprod-ca0 → … → sncprod`. 📘 `build-and-deploy/release-management.md`

---

## 7. Critical path, gates & open items

- **Sequence:** 0 → 1 → (2 ∥ 3) → 4 → 5 → 6 → 7 → 8 → 9.
- **Hard gates:** **3.6 image sync** and **7.1 Published instance** — nothing deploys to SNC without both.
- **Open items to validate:**
  1. Task 2.6 — exact mechanism to inject DCPS-sourced secrets into Pyramid's unattended JSON (Pyramid-specific contract).
  2. Confirm the resolved Artifactory image path after the first `heimdall ci` run (Task 3.2).
  3. Confirm OaaS S3 is acceptable for Pyramid's repository store given data-residency requirements.

---

## 8. Execution

Not yet implemented. Recommended order for the implementation branch: **Phase 1 → 3 → 2**, validate with `heimdall kind` before any CMDB work, keeping irreversible/outward-facing steps (image sync, Published CMDB instance) last.

### Key reference paths
- Platform docs (golden): `~/code/snc/k8s/docs-snc/content/snowsk8s/`
- Reference workload: `~/code/snc/k8s/datalake/` (`.gitlab-ci.yml`, `.tokenkeeper.yaml`, `.heimdall-sites.yaml`, `workload/heimdall.yaml`, `workload/{config,charts,overlays,stubs}/`)
- This chart source: this repo (`templates/`, `values.yaml`, `Chart.yaml`)
