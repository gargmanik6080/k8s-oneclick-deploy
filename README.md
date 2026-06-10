# k8s-oneclick-deploy

One-click deployment of a Hello World microservice to AWS EKS, provisioned with Terraform, deployed via Helm, and
monitored with Prometheus + Grafana — all driven from a single GitHub Actions workflow.

> Status: scaffolding. Full run guide, architecture diagram, and known limitations are added in later commits.

## Layout

```
app/                   Hello World Go service (exposes / and /metrics)
terraform/             VPC + EKS (Terraform)
helm/hello-world/      Helm chart for the app (+ ServiceMonitor + Grafana dashboard)
monitoring/            kube-prometheus-stack values
.github/workflows/     apply.yml (deploy) + destroy.yml (teardown)
```
