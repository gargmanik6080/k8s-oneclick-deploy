# k8s-oneclick-deploy

One-click deployment of a **Hello World** microservice to **AWS EKS** — provisioned with **Terraform**,
deployed via **Helm**, and monitored with **Prometheus + Grafana**, all driven from a single
**GitHub Actions** workflow.

Trigger one workflow → get a live, curlable HTTP endpoint on EKS plus a Grafana instance showing
both app metrics and cluster health.

## Contents

- [What it does](#what-it-does)
- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Required GitHub repo secrets](#required-github-repo-secrets)
- [Run it](#run-it)
- [Design notes](#design-notes)
- [Known limitations](#known-limitations)

## What it does

Running the `apply` workflow performs, end to end:

1. **Preflight** — validates AWS credentials, region, and that `m3.medium` is offered there (fails fast).
2. **Build & push** the app image to Docker Hub.
3. **Provision** a VPC + EKS cluster with Terraform (managed `m3.medium` node group).
4. **Install** a trimmed `kube-prometheus-stack` (Prometheus, Grafana, node-exporter, kube-state-metrics).
5. **Deploy** the app via its Helm chart (Deployment + LoadBalancer Service + ServiceMonitor + Grafana dashboard).
6. **Report** the app's and Grafana's LoadBalancer URLs (and the Prometheus port-forward command).

## Architecture

```
GitHub Actions (workflow_dispatch)
│
├── apply.yml ──────────────────────────────────────────────┐
│     AWS creds (repo secrets, session token optional)       │
│       ├─ preflight: sts get-caller-identity, AZ/EKS probe  │
│       ├─ docker build → Docker Hub (images:hello-world-<sha>)
│       ├─ terraform apply → VPC + EKS (m3.medium ×3, AZ-filtered)
│       ├─ aws eks update-kubeconfig                          │
│       ├─ helm: kube-prometheus-stack  (monitoring/values.yaml)
│       ├─ helm: hello-world chart  (--set image.tag=<sha>)   │
│       └─ upload terraform.tfstate artifact ────────────────┘
│
└── destroy.yml
      ├─ destroy:     restore state → helm uninstall (release ELB) → terraform destroy
      └─ purge-state: delete the stale state artifact (sandbox already reaped resources)

         ┌─────────────────────── EKS cluster ───────────────────────┐
         │  ns: hello-world           ns: monitoring                  │
         │  ┌───────────────┐         ┌──────────────┐                │
         │  │ Deployment    │ /metrics│ Prometheus   │── scrapes ──┐  │
         │  │ (2 pods)      │◀────────│ (ServiceMon.) │             │  │
         │  └──────┬────────┘         └──────┬───────┘             │  │
         │         │ LoadBalancer            │                     │  │
         │    ┌────▼─────┐              ┌─────▼──────┐   dashboard  │  │
         │    │  ELB     │              │  Grafana   │◀─ ConfigMap ─┘  │
         │    └────┬─────┘              └────────────┘ (sidecar)      │
         └─────────┼──────────────────────────────────────────────────┘
                   │
              curl http://<elb>/  → "Hello World"
```

## Repository layout

```
app/                   Hello World Go service (/ , /healthz , /metrics) + Dockerfile
terraform/             VPC + EKS via terraform-aws-modules (m3.medium, AZ-filtered)
helm/hello-world/      App Helm chart: Deployment, LoadBalancer Service,
                       ServiceMonitor, Grafana dashboard ConfigMap
monitoring/            Trimmed kube-prometheus-stack values
.github/workflows/     apply.yml (deploy) + destroy.yml (teardown)
```

## Prerequisites

- An AWS account/sandbox that allows EKS and `m3.medium` instances in `us-east-1` / `us-east-2` / `us-west-2`.
- A Docker Hub account with a repository named `images` (image tags distinguish builds).
- This repo on GitHub with the secrets below.

## Required GitHub repo secrets

Set these under **Settings → Secrets and variables → Actions**. In the O'Reilly sandbox the AWS creds
**rotate hourly**, so refresh them before each run.

| Secret | Required | Notes |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | yes | From the sandbox session. |
| `AWS_SECRET_ACCESS_KEY` | yes | From the sandbox session. |
| `AWS_SESSION_TOKEN` | only if temporary creds | Leave unset for a long-lived IAM user key. |
| `DOCKERHUB_USERNAME` | yes | Docker Hub login; image goes to `docker.io/<user>/images`. |
| `DOCKERHUB_TOKEN` | yes | Docker Hub access token (used for push **and** the in-cluster pull secret). |

> **Region is a workflow input, not a secret.** It's chosen at *Run workflow* time (`us-east-1`,
> `us-east-2`, or `us-west-2`; default `us-east-1`). Keeping it out of secrets means it isn't masked as
> `***` in the run summary and the ELB URLs stay clickable.

## Run it

**Deploy**

1. Set the secrets above.
2. Actions → **apply** → *Run workflow*.
3. When it finishes, the run **Summary** shows:
   - `App URL: http://<app-elb-hostname>/`
   - `Grafana (admin / admin): http://<grafana-elb-hostname>/`

**Verify**

```bash
curl http://<app-elb-hostname>/          # → Hello World
curl http://<app-elb-hostname>/metrics   # → Prometheus metrics

# Grafana — open the LoadBalancer URL from the run Summary (admin / admin):
#   http://<grafana-elb-hostname>/
#  - "Hello World Service" dashboard: request rate, p95 latency, ready pods, status codes
#  - built-in Kubernetes dashboards: node/pod/cluster health

# Prometheus stays ClusterIP (no public auth) — reach it via port-forward:
aws eks update-kubeconfig --region <region> --name oneclick-eks
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090
# open http://localhost:9090 → Status → Targets: the hello-world ServiceMonitor should be UP
```

**Tear down**

Actions → **destroy** → *Run workflow*:
- `mode = destroy` — tears down the live cluster (uninstalls Helm releases first so the app ELB is
  released, then `terraform destroy`).
- `mode = purge-state` — use when the sandbox already expired the resources; deletes the stale
  Terraform state artifact so the next `apply` starts clean.

## Design notes

- **`m3.medium` nodes.** It is the only sandbox-allowed type with meaningful RAM (1 vCPU / 3.75 GiB).
  Terraform filters AZs with `aws_ec2_instance_type_offerings` because some AZs (e.g. `us-east-1e`) don't
  offer it, which would otherwise fail node-group creation.
- **Trimmed monitoring.** To fit a 3-node, 1-vCPU-per-node cluster: Alertmanager and unreachable EKS
  control-plane scrape jobs are disabled, Prometheus retention is 3h, and resource requests are small.
  `serviceMonitorSelectorNilUsesHelmValues: false` lets Prometheus scrape the app's ServiceMonitor in
  another namespace; the Grafana sidecar watches **all** namespaces for dashboard ConfigMaps.
- **Docker Hub instead of ECR.** The sandbox locks ECR to private repos with a fixed registry policy, so
  the image lives on Docker Hub and the workflow creates an in-cluster `dockerhub-pull` secret.
- **Local state as an artifact.** No remote backend is assumed; `terraform.tfstate` is uploaded/downloaded
  between runs as a workflow artifact.

## Known limitations

- **Rotating creds.** Refresh the AWS secrets before each run. A run started late in a session may have
  creds expire mid-provision — re-run after refreshing.
- **Not production sizing.** Tiny nodes mean trimmed monitoring (no Alertmanager, 3h retention, ephemeral
  Prometheus storage). Bump `desired_size` / `node_count` if pods stay `Pending`.
- **Teardown ordering.** Run `destroy` before the sandbox reaps resources. If it already did, use
  `purge-state` to clear the stale artifact.
- **Provisioning time.** EKS is the long pole (~12–15 min); a full run is ~20–25 min.
- **Demo exposure.** The LoadBalancer and Grafana are exposed for convenience — no TLS, ingress, or
  hardened auth beyond defaults.
