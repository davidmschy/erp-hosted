# Multi-Tenant Database Infrastructure
# Aurora PostgreSQL for Multi-Tenant Architecture

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = module.vpc.database_subnets

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

# DB Parameter Group for Multi-Tenant
resource "aws_rds_cluster_parameter_group" "main" {
  name        = "${var.project_name}-${var.environment}-cluster-params"
  family      = "aurora-postgresql15"
  description = "Custom parameters for Genii ERP multi-tenant"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,pg_cron"
  }

  parameter {
    name  = "pg_stat_statements.track"
    value = "all"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-${var.environment}-rds-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "PostgreSQL from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds"
  }
}

# Aurora PostgreSQL Cluster (Multi-AZ)
resource "aws_rds_cluster" "main" {
  cluster_identifier     = "${var.project_name}-${var.environment}-cluster"
  engine                 = "aurora-postgresql"
  engine_version         = "15.4"
  engine_mode            = "provisioned"
  database_name          = "genii_erp"
  master_username        = "genii_admin"
  master_password        = random_password.db_master.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  backup_retention_period = 35
  preferred_backup_window = "03:00-04:00"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  deletion_protection = var.environment == "production"
  skip_final_snapshot = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "${var.project_name}-${var.environment}-final" : null

  storage_encrypted = true

  serverlessv2_scaling_configuration {
    min_capacity = 2
    max_capacity = 64
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-cluster"
    TenantScope = "multi"
  }
}

# Aurora Writer Instance
resource "aws_rds_cluster_instance" "writer" {
  identifier           = "${var.project_name}-${var.environment}-writer"
  cluster_identifier   = aws_rds_cluster.main.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.main.engine

  performance_insights_enabled    = true
  performance_insights_retention_period = 7

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.project_name}-${var.environment}-writer"
    Role = "writer"
  }
}

# Aurora Reader Instance (for read scaling)
resource "aws_rds_cluster_instance" "reader" {
  count              = var.environment == "production" ? 2 : 1
  identifier         = "${var.project_name}-${var.environment}-reader-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.main.engine

  performance_insights_enabled    = true
  performance_insights_retention_period = 7

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.project_name}-${var.environment}-reader-${count.index + 1}"
    Role = "reader"
  }
}

# Random password for DB master user
resource "random_password" "db_master" {
  length  = 32
  special = false
}

# Secrets Manager for DB credentials
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/${var.environment}/db-credentials"
  description             = "Database credentials for Genii ERP"
  recovery_window_in_days = var.environment == "production" ? 7 : 0
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = aws_rds_cluster.main.master_username
    password = aws_rds_cluster.main.master_password
    host     = aws_rds_cluster.main.endpoint
    port     = 5432
    dbname   = aws_rds_cluster.main.database_name
    jdbc_url = "jdbc:postgresql://${aws_rds_cluster.main.endpoint}:5432/${aws_rds_cluster.main.database_name}"
  })
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Redis/ElastiCache for Session Management & Caching
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-cache-subnet"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "elasticache" {
  name_prefix = "${var.project_name}-${var.environment}-elasticache-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-elasticache"
  }
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.project_name}-${var.environment}-redis"
  description          = "Redis cluster for Genii ERP"

  node_type            = var.environment == "production" ? "cache.r6g.xlarge" : "cache.t4g.medium"
  port                 = 6379
  parameter_group_name = "default.redis7.cluster.on"

  automatic_failover_enabled = true
  multi_az_enabled          = var.environment == "production"

  num_cache_clusters = var.environment == "production" ? 3 : 2

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache.id]

  snapshot_retention_limit = 7
  snapshot_window         = "05:00-06:00"

  tags = {
    Name = "${var.project_name}-${var.environment}-redis"
  }
}

# S3 Bucket for Tenant Data Storage
resource "aws_s3_bucket" "tenant_data" {
  bucket = "${var.project_name}-${var.environment}-tenant-data-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tenant_data" {
  bucket = aws_s3_bucket.tenant_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tenant_data" {
  bucket = aws_s3_bucket.tenant_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tenant_data" {
  bucket = aws_s3_bucket.tenant_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Outputs
output "db_endpoint" {
  description = "Database cluster endpoint"
  value       = aws_rds_cluster.main.endpoint
}

output "db_reader_endpoint" {
  description = "Database reader endpoint"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "redis_endpoint" {
  description = "Redis primary endpoint"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "s3_bucket_name" {
  description = "Tenant data S3 bucket"
  value       = aws_s3_bucket.tenant_data.bucket
}
