# Interactive AWS architecture

Open it on GitHub Pages: https://ichcc.github.io/lab-commit/docs/architecture/. `index.html` is a standalone HTML file, so it also works when opened directly in a modern browser, with no server, package installation or AWS credentials required. Only the JetBrains Mono web font is loaded from Google Fonts.

Choose **Runtime**, **CI/CD**, or **Observability-Scaling** in the chapter rail. Use the viewer's zoom and pan controls, search for a component, and select a node to inspect its relationships and source references. Choose **Live** for animated traces and **Still** to stop them. Reduced-motion preferences are respected. Light/dark themes and SVG/raster export are available in the viewer.

## Evidence and scope

This is a curated logical architecture at the Git revision recorded in `architecture.json`, not AWS discovery or a deployment status dashboard. Runtime, CI/CD and monitoring share one stable topology; chapters focus the relevant components. The notes below list relationships that are explained rather than drawn.

| Area | Source of truth |
| --- | --- |
| VPC, two private subnets, interface/S3 endpoints | `terraform/10-network/{main,variables,security}.tf` |
| Public subnet, internet gateway, fck-nat | `terraform/10-network/nat.tf` |
| EKS, configurable API endpoint access, Fargate | `terraform/20-eks/{cluster,fargate,variables}.tf` |
| Argo CD, ALB controller, Prometheus/Grafana, KEDA | `terraform/30-platform/*.tf` |
| Private single-AZ RDS and backend IRSA | `terraform/40-data/{rds,irsa,variables}.tf` |
| Imported ACM certificate, private DNS aliases | `terraform/50-edge/{certificate,dns}.tf` |
| Windows access, SSM and CA trust | `terraform/60-windows/{instance,ssm,iam}.tf` |
| Conditional CodeBuild webhook, ECR and build logs | `terraform/70-pipeline/{codebuild,ecr}.tf` |
| Image build/push and release commit | `pipeline/buildspec.yml` |
| Application sync and image versions | `gitops/{root,apps/lab}.yaml`, `charts/lab/Chart.yaml` |
| Services, ingress, seed hook and autoscaling | `charts/lab/templates/*`, `charts/lab/values.yaml` |

The AWS boundary is a logical service grouping. ECR and the EKS control plane are managed services, not pods in a subnet. GitHub is outside AWS. RDS is single AZ even though its subnet group spans two private subnets. Region/CIDRs/versions describe the repository's lab configuration and defaults; overrides can change them.

To keep the overview readable, some relationships are explained here and in the diagram cards rather than drawn:

- Argo CD syncs `charts/lab` into namespace `lab`, with automated prune/self-heal. It reaches GitHub through fck-nat. Its configured GitOps repository is `ichcc/lab-commit`.
- CodeBuild pushes VERSION-tagged images to ECR and commits Chart.yaml changes to GitHub using `[skip ci]`. Webhooks accept pushes changing `VERSION` or `apps/` and exclude that release commit. CodeBuild/source credentials require `github_token_ready=true`.
- Fargate pulls application images and platform cache/mirror images through ECR endpoints; S3 uses the gateway endpoint. The frontend itself does not perform image pulls.
- Windows uses SSM/Fleet Manager and private DNS to access the internal ALB. ALB terminates ACM TLS, redirects port 80, and serves frontend, Argo CD and Grafana. DNS ALB aliases require `alb_ready=true`.
- Backend and the seed Job use the backend service account/IRSA to fetch the RDS-managed password from Secrets Manager. Only EKS cluster security-group traffic is permitted on database port 5432.
- KEDA queries `sum(rate(http_requests_total{namespace="lab"}[1m]))`, threshold 10, every 15s; its ScaledObject/HPA scales frontend from 1 to 4 replicas, with 60s cooldown/stabilization. The scaling arrow represents this controller relationship.
- Prometheus also receives kube-state-metrics and cAdvisor data via the API proxy. Prometheus/Grafana storage is ephemeral. CodeBuild has CloudWatch logs with 7-day retention; this is not a general pod-log pipeline.

## Updating the diagram

`architecture.json` is the editable specification. `index.html` is generated using Archify 2.17; do not edit the generated HTML. No application build or deployment changes are needed.

With the Archify skill installed, from the repository root:

```bash
ARCHIFY="$HOME/.agents/skills/archify/bin/archify.mjs"
node "$ARCHIFY" validate architecture docs/architecture/architecture.json --repo-root . --quality showcase --json
node "$ARCHIFY" deliver architecture docs/architecture/architecture.json docs/architecture/index.html --repo-root . --quality showcase --json > docs/architecture/delivery.json
node "$ARCHIFY" visual-check docs/architecture/index.html --json
```

When updating infrastructure, update the specification facts, source references and revision together. Inspect the rendered diagram after generation. `delivery.json` records artifact/specification digests and deterministic checks; `index.visual-check.json` separately records browser evidence. The current delivery passed all nine artifact checks with no composition errors or warnings. Automated browser inspection passed containment, readability, viewer chrome and captures at 1440x900, 1600x1000, 1920x1080 and 2048x1320 in light and dark themes; the screenshots are in `index.visual-check.*.png`.
