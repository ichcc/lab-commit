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
| 50-edge | Self-signed cert in ACM, private Route53 zone | todo |
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

## Cost control

Destroy stacks in reverse order at the end of every session:

```bash
cd terraform/<stack>
terraform destroy
```

Delete Kubernetes ingresses before destroying the VPC, or load balancer ENIs will block deletion.
