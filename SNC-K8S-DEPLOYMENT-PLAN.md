# Pyramid Analytics SNC K8s Deployment Plan

> Status: prototype implementation scaffolded
> Date: 2026-06-02
> Guideline source: `~/code/snc/k8s/docs-snc/content/snowsk8s/`
> Reference workload: `~/code/snc/k8s/datalake/`

This repository now has two tracks:

- **Lab prototype**: prove Pyramid Analytics in `kind`, then one SNC lab cluster.
- **Production deployment**: gated follow-on work using managed database, production object storage, CMDB/CHG, production image registry, observability, and rollout controls.

The current implementation adds the downstream Heimdall scaffold under `workload/`, keeps the upstream chart at the repo root, and copies the fixed chart into `workload/charts/pyramid/`.

---

## Implemented Scaffold

### Repository layout

- `.heimdall-sites.yaml` points Heimdall to `workload/`.
- `.gitlab-ci.yml` and `.tokenkeeper.yaml` define Heimdall CI image sync to Artifactory.
- `workload/heimdall.yaml` defines releases:
  - `namespace-creation` for local only.
  - `shared-resources`.
  - `postgresql` for lab only.
  - `pyramid`.
- `workload/charts/pyramid/` is the SNC-ready copy of the Pyramid chart.
- `workload/charts/postgresql/` is lab-only Postgres on RWO storage.
- `workload/charts/shared-resources/` contains DCPS and network policy scaffolding.
- `workload/overlays/*/{local,snc-lab,prod,cmdb,ci}/` separate lab/prod configuration.
- `workload/stubs/*/` hold placeholder CMDB values for local, lab, and prod render flows.

### Chart fixes applied

- `service.annotations` now renders on the Pyramid `LoadBalancer`.
- `service.type` is configurable, so local can use `ClusterIP` and SNC can use `LoadBalancer`.
- Bundled Prometheus is controlled by `prometheus.enabled`; SNC overlays disable it.
- All hardcoded `namespace: {{ .Release.Namespace }}` fields were removed from Pyramid templates.
- Container security context now drops all Linux capabilities.
- `unattended.createSecret` allows SNC overlays to disable the inline Secret and let External Secrets own it.
- NFS/GKE Filestore templates remain in the upstream chart but are disabled for SNC by setting `storage.type: other`.

---

## Lab Prototype Plan

### Phase L0 - Local/kind render and smoke

1. Install prerequisites:
   - Heimdall.
   - Helm diff plugin through Heimdall plugins.
   - Docker or compatible local container runtime.
2. Render locally:
   - `cd workload`
   - `heimdall apply --environment=local --dry-run` or equivalent local render command.
3. Validate local rendered manifests:
   - No `ClusterRole` or `ClusterRoleBinding`.
   - No explicit `Namespace` in Pyramid chart resources.
   - No NFS/GKE Filestore PVC/PV when `storage.type: other`.
   - Pyramid service is `ClusterIP`.
4. Start kind:
   - `heimdall kind --environment=local`
   - `heimdall apply --environment=local`
5. Smoke test:
   - Confirm Postgres pod ready.
   - Confirm eight Pyramid deployments render and pods attempt startup.
   - Port-forward `pyramid:8181` and confirm WS responds.
   - Confirm first-run UI is available if unattended install remains disabled.

### Phase L1 - Lab prerequisites

1. CMDB:
   - Create Workload `pyramidanalytics`.
   - Create lab Workload Family for the prototype branch.
   - Create one lab Workload Instance and set state to `Published` only when ready to deploy.
   - Create Service Template `pyramid-web`.
   - Create/verify Service Instance and port `8181`.
   - Create lab Storage Instance for Postgres titanium PVC.
2. Object storage:
   - Request OaaS S3-compatible lab bucket.
   - Record bucket, endpoint, region, access key, and secret in DCPS.
3. Secrets:
   - Create DCPS API key secret `pyramid-dcps-apikey`.
   - Create DCPS credential entries:
     - `pyramid-db-credentials`.
     - `pyramid-admin-credentials`.
     - `pyramid-license`.
     - `pyramid-s3-credentials`.
4. Image sync:
   - Ensure Token Keeper has granted the project write access to `docker-local`.
   - Run GitLab pipeline with `sync_images: true`.
   - Confirm Pyramid images and `postgres:17` are present under the project Artifactory path.

### Phase L2 - SNC lab deployment

1. Fill `workload/stubs/snc-lab/workload-definition.yaml` or CMDB config with:
   - `heimdall.workload.services.pyramid-web.id`.
   - `heimdall.workload.storage.postgresql.id`.
   - `heimdall.workload.config.storage.s3Endpoint`.
   - DCPS remote reference names if different from defaults.
2. Deploy:
   - Use `snc-lab` environment.
   - `shared-resources` creates network policies and DCPS resources.
   - `postgresql` creates lab-only single-pod Postgres on titanium.
   - `pyramid` deploys Pyramid with Artifactory images and `LoadBalancer` annotations.
3. Validate:
   - Glitnir accepts rendered manifests.
   - CCM provisions private ADC LB.
   - ADC health check uses HTTP, port `8181`, path `/`, and `^2[0-9]{2}$`.
   - Network policies allow only DNS, ADC ingress, intra-workload traffic, Postgres egress, S3 egress, and radium metrics.
   - WS is reachable through the lab FQSN.
   - Pyramid setup completes through first-run UI or unattended path once vendor S3 endpoint support is confirmed.

### Lab acceptance criteria

- No cluster-scoped RBAC is rendered for SNC lab.
- No untrusted image registry is rendered for SNC lab.
- No RWX/NFS/GKE storage is rendered for SNC lab.
- Lab Postgres is clearly treated as prototype-only.
- Pyramid can store repository data in object storage or the deployment remains blocked with documented manual setup.
- Metrics endpoint is reachable by radium through policy.

---

## Production Deployment Plan

Production is not a direct promotion of the lab dependency stack. It must use a managed DB and production-approved object storage/images.

### Phase P0 - Architecture gates

1. Managed database:
   - Choose Postgres or SQL Server.
   - Confirm owner, HA, backup, restore test, DR model, monitoring, and access path.
   - Store credentials in production DCPS.
2. Object storage:
   - Confirm production endpoint, bucket, replication, data residency, CA requirements, and ownership.
   - Store credentials in production DCPS.
3. Service exposure:
   - Confirm private vs public IP space.
   - Confirm DNS names, service scope, TLS expectations, and health check behavior.
   - If production ADC requires HTTPS but Pyramid only serves HTTP on `8181`, add a TLS termination or app TLS decision before prod.
4. Images:
   - Confirm production Artifactory path such as `docker-prd-local` or another approved production-accessible registry.
   - Confirm vulnerability scanning and promotion process.

### Phase P1 - Production overlay completion

1. Keep `postgresql` release disabled in `prod`.
2. Fill production CMDB config:
   - `heimdall.workload.config.database.endpoint`.
   - `heimdall.workload.config.storage.s3Endpoint`.
   - production DCPS remote refs.
   - production Service Instance id.
3. Replace placeholder production image repo if the approved registry differs from the scaffold.
4. Set production resource requests/limits from load testing.
5. Enable unattended install only after Pyramid S3-compatible endpoint support is validated.

### Phase P2 - Production CMDB and rollout

1. Create production Workload Family and Workload Instances through required CHG process.
2. Create or verify Service Templates, Service Instances, External Service Names, and Service Scope.
3. Render and scan production manifests before publishing instances.
4. Promote progressively:
   - `release/sncsubprod-ca0`
   - `release/sncsubprod-ca1`
   - `release/sncsubprod-ca2`
   - `release/sncsubprod`
   - `release/sncprod-ca0`
   - continue through wider production branches only after soak.
5. Rollback by moving the affected release branch back to the last known-good commit and verifying Heimdall reconciliation.

### Production acceptance criteria

- Managed DB backup and restore are tested.
- Object storage data residency and access are approved.
- Production images are from approved production Artifactory paths.
- Glitnir scan passes.
- LB health checks, DNS, network policies, metrics, logs, and alerts are validated.
- No lab Postgres release is enabled.

---

## Open Gates

1. **Pyramid S3-compatible endpoint support**: current chart values expose bucket, region, and keys but no endpoint. Until vendor documentation confirms the unattended JSON key for endpoint, unattended S3 setup remains disabled.
2. **Production TLS**: production overlay currently assumes HTTPS health checks. Confirm whether Pyramid serves TLS directly or whether ADC/proxy termination is required.
3. **Resource sizing**: current requests are chart defaults and lab placeholders. Production sizing must come from load testing.
4. **Secret schema**: shared-resources currently mirrors DCPS results into Kubernetes Secrets. Final unattended generation must be completed only after Pyramid’s exact unattended JSON contract is confirmed.

---

## Verification Commands

Use these after filling environment-specific CMDB values:

```shell
helm template pyramid workload/charts/pyramid --namespace snowsk8s-pyramid --values workload/overlays/pyramid/local/values.yaml
helm template shared-resources workload/charts/shared-resources --namespace snowsk8s-pyramid --values workload/overlays/shared-resources/local/values.yaml
helm template postgresql workload/charts/postgresql --namespace snowsk8s-pyramid --values workload/overlays/postgresql/local/values.yaml
```

Static checks to run against rendered manifests:

```shell
rg 'kind: (Namespace|ClusterRole|ClusterRoleBinding)' rendered.yaml
rg 'ReadWriteMany|google-filestore|storageClassName: manual|storageClassName: ""' rendered.yaml
rg 'image: "(pyramidanalytics|prom/prometheus|postgres)' rendered.yaml
```
