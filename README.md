# Lab-Commit: EKS Scaling and Pipeline

Private EKS (Fargate only) platform on AWS, built with Terraform. Work is split into numbered stacks applied in order. Each stack has its own state key in one S3 bucket.

## Status

| Stack | Content | State |
|---|---|---|
| 00-bootstrap | State bucket, budget alarms | done |
| 10-network | VPC, 2 private subnets, endpoints, security groups | done |
| 20-eks | Cluster 1.35, Fargate profiles, IRSA, ECR pull-through cache | done |
| 30-platform | Load Balancer Controller, Argo CD, KEDA, Prometheus, Grafana | done |
| 40-data | RDS PostgreSQL | todo |
| 50-edge | Self-signed cert in ACM, private Route53 zone | todo |
| 60-windows | Windows instance via SSM | todo |
| 70-pipeline | CodePipeline, CodeBuild, ECR | todo |

## Prerequisites

- AWS CLI v2, Terraform >= 1.10, kubectl, Helm 3, Docker, Git
- AWS credentials with a privileged role assumed in the console or CLI
- A new GitHub repository for this project
- A region where EKS 1.35 and Fargate are available

Verify the region before anything else:

```bash
export AWS_REGION=eu-central-1
aws eks describe-addon-versions --kubernetes-version 1.35 --region "$AWS_REGION" --query 'addons[0].addonName'
aws sts get-caller-identity
```

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
- 2 private subnets in 2 AZs, no internet gateway, no NAT
- One route table with local routes and the S3 gateway endpoint
- Interface endpoints (ECR, STS, Logs, EC2, ELB, SSM, Secrets Manager, EKS, CodeBuild, KMS) in both subnets
- Security groups: endpoints (443 from VPC), ALB (80/443 from VPC), Windows (egress only to VPC and S3)

Interface endpoints are the largest hourly cost in this stack. Remove entries from `interface_endpoints` that a later stack does not need.

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

## Cost control

Destroy stacks in reverse order at the end of every session:

```bash
cd terraform/<stack>
terraform destroy
```

Delete Kubernetes ingresses before destroying the VPC, or load balancer ENIs will block deletion.
