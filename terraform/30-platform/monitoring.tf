resource "random_password" "grafana" {
  length  = 24
  special = false
}

locals {
  kubelet_proxy_relabel = yamlencode([
    {
      target_label = "__address__"
      replacement  = "kubernetes.default.svc:443"
    },
    {
      source_labels = ["__meta_kubernetes_node_name", "__metrics_path__"]
      regex         = "(.+);(.+)"
      target_label  = "__metrics_path__"
      replacement   = "/api/v1/nodes/$1/proxy$2"
    },
  ])
}

resource "helm_release" "prometheus" {
  name             = "prometheus"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  version          = var.chart_versions["prometheus"]
  timeout          = 900

  values = [yamlencode({
    alertmanager             = { enabled = false }
    prometheus-pushgateway   = { enabled = false }
    prometheus-node-exporter = { enabled = false }
    configmapReload = {
      prometheus = { image = { repository = "${local.ecr}/quay/prometheus-operator/prometheus-config-reloader" } }
    }
    kube-state-metrics = {
      image     = { registry = local.ecr, repository = "k8s/kube-state-metrics/kube-state-metrics" }
      resources = { requests = { cpu = "250m", memory = "512Mi" } }
    }
    server = {
      image            = { repository = "${local.ecr}/quay/prometheus/prometheus" }
      global           = { scrape_interval = "15s", evaluation_interval = "15s" }
      retention        = "6h"
      persistentVolume = { enabled = false }
      resources        = { requests = { cpu = "500m", memory = "1Gi" } }
    }
    scrapeConfigs = {
      kubernetes-nodes          = { post_relabel_configs = local.kubelet_proxy_relabel }
      kubernetes-nodes-cadvisor = { post_relabel_configs = local.kubelet_proxy_relabel }
    }
    extraManifests = [
      yamlencode({
        apiVersion = "rbac.authorization.k8s.io/v1"
        kind       = "ClusterRole"
        metadata   = { name = "prometheus-server-nodes-proxy" }
        rules = [{
          apiGroups = [""]
          resources = ["nodes/proxy"]
          verbs     = ["get"]
        }]
      }),
      yamlencode({
        apiVersion = "rbac.authorization.k8s.io/v1"
        kind       = "ClusterRoleBinding"
        metadata   = { name = "prometheus-server-nodes-proxy" }
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io"
          kind     = "ClusterRole"
          name     = "prometheus-server-nodes-proxy"
        }
        subjects = [{
          kind      = "ServiceAccount"
          name      = "prometheus-server"
          namespace = "monitoring"
        }]
      }),
    ]
  })]

  depends_on = [helm_release.lbc]
}

resource "helm_release" "grafana" {
  name       = "grafana"
  namespace  = "monitoring"
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "grafana"
  version    = var.chart_versions["grafana"]
  timeout    = 900

  values = [yamlencode({
    image         = { registry = local.ecr, repository = "mirror/grafana/grafana", tag = var.grafana_image_tag }
    adminPassword = random_password.grafana.result
    persistence   = { enabled = false }
    resources     = { requests = { cpu = "250m", memory = "512Mi" } }
    datasources = {
      "datasources.yaml" = {
        apiVersion = 1
        datasources = [{
          name      = "Prometheus"
          uid       = "prometheus"
          type      = "prometheus"
          access    = "proxy"
          url       = "http://prometheus-server.monitoring.svc.cluster.local"
          isDefault = true
        }]
      }
    }
    dashboardProviders = {
      "dashboardproviders.yaml" = {
        apiVersion = 1
        providers = [{
          name            = "default"
          orgId           = 1
          folder          = ""
          type            = "file"
          disableDeletion = false
          options         = { path = "/var/lib/grafana/dashboards/default" }
        }]
      }
    }
    dashboards = {
      default = {
        lab-commit = { json = file("${path.module}/dashboards/lab-commit.json") }
      }
    }
  })]

  depends_on = [helm_release.prometheus]
}
