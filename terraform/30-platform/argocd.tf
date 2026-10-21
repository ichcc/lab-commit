resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_versions["argocd"]
  timeout          = 900

  values = [yamlencode({
    global        = { image = { repository = "${local.ecr}/quay/argoproj/argocd" } }
    redis         = { image = { repository = "${local.ecr}/ecr-public/docker/library/redis" } }
    dex           = { enabled = false }
    notifications = { enabled = false }
    configs = {
      params = { "server.insecure" = true }
    }
    controller     = { resources = { requests = { cpu = "250m", memory = "512Mi" } } }
    server         = { resources = { requests = { cpu = "250m", memory = "512Mi" } } }
    repoServer     = { resources = { requests = { cpu = "250m", memory = "512Mi" } } }
    applicationSet = { resources = { requests = { cpu = "250m", memory = "512Mi" } } }
  })]

  depends_on = [helm_release.lbc]
}
