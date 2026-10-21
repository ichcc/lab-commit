resource "aws_ecr_pull_through_cache_rule" "this" {
  for_each = var.pull_through_cache

  ecr_repository_prefix = each.key
  upstream_registry_url = each.value
}
