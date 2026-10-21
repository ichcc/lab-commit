resource "helm_release" "keda" {
  name             = "keda"
  namespace        = "keda"
  create_namespace = true
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.chart_versions["keda"]
  timeout          = 900

  values = [yamlencode({
    image = {
      keda             = { registry = local.ecr, repository = "mirror/kedacore/keda", tag = var.keda_image_tag }
      metricsApiServer = { registry = local.ecr, repository = "mirror/kedacore/keda-metrics-apiserver", tag = var.keda_image_tag }
      webhooks         = { registry = local.ecr, repository = "mirror/kedacore/keda-admission-webhooks", tag = var.keda_image_tag }
    }
    resources = {
      operator      = { requests = { cpu = "250m", memory = "512Mi" } }
      metricServer  = { requests = { cpu = "250m", memory = "512Mi" } }
      webhooks      = { requests = { cpu = "250m", memory = "512Mi" } }
    }
  })]

  depends_on = [helm_release.lbc]
}
