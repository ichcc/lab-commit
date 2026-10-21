resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-db"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name = "${var.project}-db"
  }
}

resource "aws_security_group" "db" {
  name        = "${var.project}-db"
  description = "PostgreSQL"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${var.project}-db"
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_cluster" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = local.cluster_sg_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS pods"
}

resource "aws_db_instance" "this" {
  identifier                  = "${var.project}-db"
  engine                      = "postgres"
  engine_version              = var.db_engine_version
  instance_class              = var.db_instance_class
  allocated_storage           = var.db_allocated_storage
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = var.db_name
  username                    = var.db_username
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.this.name
  vpc_security_group_ids      = [aws_security_group.db.id]
  publicly_accessible         = false
  multi_az                    = false
  backup_retention_period     = 1
  auto_minor_version_upgrade  = true
  apply_immediately           = true
  skip_final_snapshot         = true
  deletion_protection         = false

  tags = {
    Name = "${var.project}-db"
  }
}
