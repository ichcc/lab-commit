# Lab-Commit: EKS Scaling and Pipeline

Private EKS (Fargate only) platform on AWS, built with Terraform. Work is split into numbered stacks applied in order. Each stack has its own state key in one S3 bucket.

## Status

| Stack | Content | State |
|---|---|---|
| 00-bootstrap | State bucket, budget alarms | done |
| 10-network | VPC, 2 private subnets, endpoints, security groups | done |
| 20-eks | Cluster 1.35, Fargate profiles, IRSA, ECR pull-through cache | done |
| 30-platform | Load Balancer Controller, Argo CD, KEDA, Prometheus, Grafana | done |
| 40-data | RDS PostgreSQL, database secret, backend IRSA role | done |
| 50-edge | Self-signed CA and certificate in ACM, private Route53 zone, ALB records | done |
| 60-windows | Windows instance via SSM | todo |
| 70-pipeline | CodePipeline, CodeBuild, ECR | todo |

## Prerequisites

- AWS CLI v2, Terraform >= 1.10, kubectl, Helm 3, Docker, Git
- AWS credentials with a privileged role assumed in the console or CLI
- A new GitHub repository for this project
- A region where EKS 1.35 and Fargate are available

The lab runs in `il-central-1` (Tel Aviv). It is an opt-in region, so enable it first in the account settings. CodeConnections is not offered in this region, which shapes the pipeline design in stack 70.

Verify the region before anything else:

```bash
export AWS_REGION=il-central-1
aws account get-region-opt-status --region-name "$AWS_REGION"
aws eks describe-addon-versions --kubernetes-version 1.35 --region "$AWS_REGION" --query 'addons[0].addonName'
aws sts get-caller-identity
```

Expected: `ENABLED`, an addon name, and your account id.

## Step 0: remove the default VPC

```bash
./scripts/delete-default-vpc.sh "$AWS_REGION"
```

The script detaches and deletes the internet gateway, deletes the subnets, then deletes the VPC. It exits cleanly when no default VPC exists.

## Step 1: bootstrap state and budget

```bash
cd terraform/00-bootstrap
cp example.tfvars terraform.tfvars
terraform init
terraform apply
```

Edit `terraform.tfvars` first: set `region`, `budget_usd` to a value below your credit balance, and `budget_email`. Bootstrap uses local state. Keep the generated `terraform.tfstate` file or re-import the bucket if you lose it.

Note the `state_bucket` output.

## Step 2: network

```bash
cd ../10-network
cp backend.hcl.example backend.hcl
cp example.tfvars terraform.tfvars
```

Fill `backend.hcl` with the bucket name and region, then:

```bash
terraform init -backend-config=backend.hcl
terraform apply
```

Result:

- VPC `10.20.0.0/16`, DNS hostnames enabled
- 2 private subnets in 2 AZs holding every workload
- 1 small public subnet that contains only the fck-nat instance, with an internet gateway
- fck-nat (t4g.micro, ASG-backed) giving the private route table a default route for outbound traffic, so Argo CD, CodeBuild and Helm can reach GitHub
- One private route table with local routes, the S3 gateway endpoint and the NAT default route
- Interface endpoints (ECR, STS, Logs, EC2, ELB, SSM, Secrets Manager, EKS, CodeBuild, KMS) in both subnets
- Security groups: endpoints (443 from VPC), ALB (80/443 from VPC), Windows (egress only to VPC and S3, so it has no Internet access)

Nothing in the VPC is reachable from the Internet: the public subnet has no workloads, the load balancer is internal, and inbound traffic to the NAT instance is limited to the VPC CIDR.

The fck-nat module is pinned to release `v1.6.1` through `?ref=` in `nat.tf`. To upgrade, change the tag, run `terraform init -upgrade` and review the plan for NAT replacement. Provider versions are pinned by the committed `.terraform.lock.hcl` in each stack.

Interface endpoints are the largest hourly cost in this stack. With NAT in place, ECR, STS, Logs, EKS, EC2, ELB, Secrets Manager, KMS and CodeBuild endpoints are optional and can be removed from `interface_endpoints` to save money. Keep `ssm`, `ssmmessages` and `ec2messages` for the Windows instance.

## Step 3: EKS

```bash
cd ../20-eks
cp backend.hcl.example backend.hcl
cp example.tfvars terraform.tfvars
```

Fill `backend.hcl` and `terraform.tfvars`. `admin_cidrs` must contain your current public IP as `x.x.x.x/32`, because Terraform and kubectl reach the API through the public endpoint during build.

```bash
terraform init -backend-config=backend.hcl
terraform apply
aws eks update-kubeconfig --name lab-commit-eks --region "$AWS_REGION"
kubectl get pods -A
```

Result:

- Cluster `lab-commit-eks`, Kubernetes 1.35, API authentication mode `API`, creator has admin
- No node groups. One Fargate profile per namespace: `default`, `kube-system`, `argocd`, `keda`, `monitoring`, `lab`
- CoreDNS addon configured to run on Fargate
- OIDC provider for IRSA (EKS Pod Identity is not supported on Fargate)
- ECR pull-through cache rules: `ecr-public/`, `k8s/`, `quay/`. Docker Hub and GHCR need registry credentials in Secrets Manager and are not configured
- Cluster security group accepts the ALB security group on ports 80, 3000, 8000, 8080, 9090 only

Image paths for later stacks follow this pattern:

```
<account>.dkr.ecr.<region>.amazonaws.com/quay/prometheus/prometheus:<tag>
<account>.dkr.ecr.<region>.amazonaws.com/k8s/metrics-server/metrics-server:<tag>
```

The first pull of each image creates the cached repository.

CoreDNS can stay in Pending for a few minutes after the Fargate profile is created. If it does not start:

```bash
kubectl -n kube-system rollout restart deployment coredns
```

To lock the API down at the end of the lab set `public_endpoint = false` and re-apply from a host inside the VPC.

## Step 4: mirror images that the pull-through cache cannot serve

Fargate pods in private subnets pull only from ECR. The pull-through cache covers `public.ecr.aws`, `registry.k8s.io` and `quay.io` without credentials. KEDA (GHCR) and Grafana (Docker Hub) need credentials for a cache rule, so they are copied once instead:

```bash
./scripts/mirror-images.sh "$AWS_REGION"
```

Requirements: Docker with buildx, AWS CLI, and internet access from your workstation. The script logs in to ECR, creates `mirror/<name>` repositories and copies the multi-arch manifests listed in `scripts/mirror-images.txt`. Tags in that file must match `keda_image_tag` and `grafana_image_tag` in the platform stack.

## Step 5: platform

```bash
cd terraform/30-platform
cp backend.hcl.example backend.hcl
cp example.tfvars terraform.tfvars
terraform init -backend-config=backend.hcl
terraform apply
```

Terraform runs Helm from your workstation, so the EKS public endpoint must still allow your IP (`admin_cidrs` in stack 20) and `aws` must be on `PATH` for token generation. Charts download from the public Helm repositories on your machine. Images come from ECR.

Installed releases:

| Release | Namespace | Notes |
|---|---|---|
| aws-load-balancer-controller | kube-system | IRSA role, Shield/WAF disabled, VPC id and region set explicitly because Fargate has no instance metadata |
| keda | keda | Images from `mirror/kedacore/*` |
| argocd | argocd | Dex and notifications disabled, `server.insecure=true` so the ALB terminates TLS |
| prometheus | monitoring | No node-exporter, Alertmanager or Pushgateway (DaemonSets and PVCs do not fit Fargate). Retention 6h, no persistent volume. Pod CPU and memory come from kubelet cAdvisor through the API server proxy, replica counts from kube-state-metrics |
| grafana | monitoring | Prometheus datasource and the `Lab-Commit` dashboard are provisioned from `dashboards/lab-commit.json` |

Check:

```bash
kubectl get pods -A
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
terraform output -raw grafana_admin_password; echo
```

Until the ALB ingress exists (stack 50) use port forwarding:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
kubectl -n monitoring port-forward svc/grafana 3000:80
```

Fargate pods take one to two minutes to start, so the first apply can take about 10 minutes. If a release times out, run `terraform apply` again.

The dashboard panels expect the `lab` namespace, deployments named `frontend` and `backend`, and an `http_requests_total` metric exposed by the frontend with Prometheus scrape annotations.

## Step 6: data

Prerequisites: stacks 10 and 20 applied, because this stack reads their remote state (VPC, private subnets, cluster security group, OIDC provider).

```bash
cd terraform/40-data
cp backend.hcl.example backend.hcl
cp example.tfvars terraform.tfvars
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

RDS takes about 5 to 8 minutes to create.

Result:

- RDS PostgreSQL 18, `db.t4g.micro`, 20 GB gp3, encrypted, single AZ, in a DB subnet group over the two private subnets, `publicly_accessible = false`
- Master password generated and stored by RDS in Secrets Manager (`manage_master_user_password`), never in Terraform state or tfvars
- Security group `lab-commit-db` that allows port 5432 only from the EKS cluster security group. Fargate pods use that group, so pods can connect and nothing else in the VPC can
- IAM role `lab-commit-backend` for the `lab/backend` service account (IRSA), allowed only `GetSecretValue` and `DescribeSecret` on the database secret. Pods reach Secrets Manager through the `secretsmanager` interface endpoint
- No table is created here. The Helm chart runs a seed Job that creates `lab_values` and inserts the initial rows idempotently

Outputs used by the chart:

```bash
terraform output -raw db_endpoint
terraform output -raw db_secret_arn
terraform output -raw backend_role_arn
```

Check:

```bash
aws rds describe-db-instances --db-instance-identifier lab-commit-db \
  --query 'DBInstances[0].[DBInstanceStatus,PubliclyAccessible,StorageEncrypted,Engine,EngineVersion]'
aws secretsmanager describe-secret --secret-id "$(terraform output -raw db_secret_arn)" --query Name
```

Expected: `available`, `false`, `true`, `postgres`, `18.x`, and a secret name starting with `rds!db-`.

Troubleshooting:

- `Error reading remote state`: `state_bucket` or `region` in `terraform.tfvars` does not match the bucket from stack 00, or stack 10 or 20 was not applied.
- `InvalidParameterCombination` for the engine version: list the versions offered for the instance class and set `db_engine_version`:
  `aws rds describe-orderable-db-instance-options --engine postgres --db-instance-class db.t4g.micro --query 'OrderableDBInstanceOptions[].EngineVersion'`
- The backend logs `no pg_hba.conf entry ... no encryption`: PostgreSQL 18 on RDS enforces SSL (`rds.force_ssl = 1`). Keep `DB_SSLMODE=require` in the chart values.
- `AccessDeniedException` on `GetSecretValue`: the service account is missing the `eks.amazonaws.com/role-arn` annotation, or its namespace or name differs from `backend_namespace` and `backend_service_account`.

## Step 7: applications and chart

Two Flask services in `apps/`, packaged by the Helm chart `charts/lab`. Argo CD deploys the chart (stack 70 and `gitops/`). This step covers local tests and the chart values.

| Service | Port | Endpoints | Notes |
|---|---|---|---|
| backend | 8000 | `GET /value`, `GET /healthz` | Reads the database password from Secrets Manager with boto3 through IRSA, returns the next row of `lab_values` in a loop. The loop position is the sequence `lab_values_cursor`, so all replicas share it |
| frontend | 8080 | `GET /`, `GET /healthz`, `GET /metrics` | A background thread polls the backend every 5 seconds. `/` returns `Hello Lab-Commit <APP_VERSION> <value>`. `http_requests_total` counts only `/`, not health checks or scrapes |

`seed.py` in the backend image creates `lab_values` and the sequence and inserts the initial rows only when the table is empty. The chart runs it as a Job.

Prerequisites: Python 3.13, `uv` or `pip`, Docker, Helm 3.

### Tests

```bash
cd apps/backend
python3.13 -m venv .venv && .venv/bin/pip install -r requirements.txt -r requirements-dev.txt
PYTHONPATH=. .venv/bin/pytest -q tests

cd ../frontend
python3.13 -m venv .venv && .venv/bin/pip install -r requirements.txt -r requirements-dev.txt
PYTHONPATH=. .venv/bin/pytest -q tests
```

Expected: `6 passed` for the backend and `5 passed` for the frontend.

### Images

Both Dockerfiles use `public.ecr.aws/docker/library/python:3.13-slim` and run as UID 10001. Fargate runs x86, so build for `linux/amd64`:

```bash
docker build --platform linux/amd64 -t lab/backend:v1.0.0 apps/backend
docker build --platform linux/amd64 -t lab/frontend:v1.0.0 apps/frontend
```

Inside AWS, pass the pull-through cache path so the build does not need Docker Hub or the internet:

```bash
--build-arg BASE_IMAGE=<account>.dkr.ecr.<region>.amazonaws.com/ecr-public/docker/library/python:3.13-slim
```

The pipeline in stack 70 builds and pushes both images to the `lab/backend` and `lab/frontend` ECR repositories with the chart `appVersion` as the tag.

### Chart

| Object | Details |
|---|---|
| Deployments `frontend`, `backend` | Non-root, read-only root filesystem, requests 250m CPU and 512Mi (one Fargate 0.25 vCPU / 1 GB slot), `/healthz` probes. `APP_VERSION` comes from `.Chart.AppVersion`, and so does the image tag unless `image.tag` is set |
| Services | ClusterIP only. The backend has no Ingress |
| ServiceAccounts | `backend` carries the IRSA annotation `backend.roleArn`. `frontend` has no token mounted |
| Job `seed` | Helm `post-install,post-upgrade` hook, which Argo CD runs as a PostSync hook. Uses the backend image and service account |
| Ingress `frontend` | Internal ALB, `target-type: ip`, group `lab-commit`, ports 80 and 443 with redirect to 443, ACM certificate, host `lab-commit-task.<zone>` |
| Ingresses `argocd`, `grafana` | Same ALB group, created in the `argocd` and `monitoring` namespaces, hosts `argocd.<zone>` and `grafana.<zone>` |
| ScaledObject `frontend` | Prometheus trigger `sum(rate(http_requests_total{namespace="lab"}[1m]))`, `AverageValue` 10, 1 to 4 replicas, `cooldownPeriod` 60, scale-down stabilization 60 s and at most one pod every 30 s |

Required values, taken from Terraform outputs:

| Value | Source |
|---|---|
| `image.registry` | `terraform -chdir=terraform/20-eks output -raw ecr_registry` |
| `backend.roleArn` | `terraform -chdir=terraform/40-data output -raw backend_role_arn` |
| `db.host` | `terraform -chdir=terraform/40-data output -raw db_endpoint` |
| `db.secretArn` | `terraform -chdir=terraform/40-data output -raw db_secret_arn` |
| `ingress.certificateArn` | `terraform -chdir=terraform/50-edge output -raw certificate_arn` |
| `ingress.securityGroupId` | `terraform -chdir=terraform/10-network output -raw alb_security_group_id` |
| `zone` | private hosted zone name, default `lab.internal` |

Render and lint:

```bash
helm lint charts/lab -f my-values.yaml
helm template lab charts/lab -n lab -f my-values.yaml
```

Without the required values the render stops with a message such as `db.host is required`.

Troubleshooting:

- Pods stay `Pending`: the namespace has no Fargate profile, or the requests do not fit a Fargate size. `kubectl -n lab describe pod <pod>` shows the reason.
- `ImagePullBackOff`: the images are not pushed yet, or the tag does not match `appVersion`. `aws ecr describe-images --repository-name lab/frontend`.
- The page shows `n/a`: the backend is not ready or the seed Job has not finished. `kubectl -n lab logs deploy/backend` and `kubectl -n lab get jobs`.
- All three Ingresses in one group must carry the same scheme, certificate and security group annotations, otherwise the controller rejects the group. `kubectl -n lab describe ingress frontend` shows the error event.
- The ScaledObject is not `READY`: KEDA cannot reach Prometheus. `kubectl -n lab describe scaledobject frontend` and `kubectl -n keda logs deploy/keda-operator`. An empty query result before the first page request counts as 0 and is not an error.

## Step 8: edge (certificate and private DNS)

Prerequisites: stack 10 applied. The second phase also needs the chart synced by Argo CD, because the load balancer controller creates the ALB from the Ingresses.

The stack creates:

- A private CA (self-signed root, RSA 2048, one year) and a server certificate signed by it with SANs `lab-commit-task.<zone>`, `argocd.<zone>` and `grafana.<zone>`. A self-signed root plus a leaf is used instead of one self-signed leaf because Chrome does not accept a leaf certificate (`CA:FALSE`) as a trust anchor
- The server certificate and chain imported into ACM (`certificate_arn` output, used by the chart as `ingress.certificateArn`)
- The CA certificate in SSM Parameter Store at `/lab-commit/ca-certificate`, where the Windows instance reads it
- A private Route53 hosted zone (`zone_name`, default `lab.internal`) attached to the VPC
- After phase two, alias A records for the three hostnames pointing to the internal ALB

The private keys are generated by Terraform and live in the state file. The state bucket is encrypted and private. For anything beyond a lab, issue certificates outside Terraform.

### Phase one: certificate and zone

```bash
cd terraform/50-edge
cp backend.hcl.example backend.hcl
cp example.tfvars terraform.tfvars
terraform init -backend-config=backend.hcl
terraform apply
terraform output -raw certificate_arn
```

Keep `alb_ready = false`. Put the certificate ARN and zone name into the chart values, then let Argo CD sync (see "Pipeline and GitOps").

### Phase two: DNS records

The controller tags the shared ALB with `ingress.k8s.aws/stack = lab-commit` (the `group.name`). Wait until it exists:

```bash
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?starts_with(LoadBalancerName, 'k8s-labcommit')].[LoadBalancerName,Scheme,State.Code]"
kubectl get ingress -A
```

Expected: one load balancer, `internal`, `active`, and three Ingresses with the same address. Then:

```bash
terraform apply -var alb_ready=true
```

Or set `alb_ready = true` in `terraform.tfvars` so later applies keep the records.

### Check

```bash
aws acm describe-certificate --certificate-arn "$(terraform output -raw certificate_arn)" \
  --query 'Certificate.[Type,Status,DomainName,SubjectAlternativeNames]'
aws route53 list-resource-record-sets --hosted-zone-id "$(terraform output -raw zone_id)" \
  --query "ResourceRecordSets[?Type=='A'].[Name,AliasTarget.DNSName]"
```

Expected: `IMPORTED`, `ISSUED`, the three names, and three A records pointing to the same `internal-k8s-labcommit-...` name.

Troubleshooting:

- `no matching LB found` in phase two: the Ingresses are not reconciled yet. Check `kubectl -n lab describe ingress frontend` for controller events, for example a missing certificate ARN or a mismatch inside the group.
- `multiple LBs matched`: an older ALB with the same group tag is still being deleted. Wait and retry.
- Names do not resolve from the Windows instance: the zone must be attached to the VPC (`aws route53 get-hosted-zone --id <zone>` shows `VPCs`), and the VPC needs DNS support and DNS hostnames, which stack 10 enables.
- Destroy order: run `terraform apply -var alb_ready=false` or destroy this stack before the ALB is removed, otherwise the data source fails on the next plan.

## Cost control

Destroy stacks in reverse order at the end of every session:

```bash
cd terraform/<stack>
terraform destroy
```

Delete Kubernetes ingresses before destroying the VPC, or load balancer ENIs will block deletion.
