# Auto-scaling and Monitoring Configuration

# Cluster Autoscaler IAM Role
module "cluster_autoscaler_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                        = "${var.project_name}-${var.environment}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}

# AWS Load Balancer Controller IAM Role
module "load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.project_name}-${var.environment}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# External DNS IAM Role
module "external_dns_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                  = "${var.project_name}-${var.environment}-external-dns"
  attach_external_dns_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }
}

# CloudWatch Log Group for EKS
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.project_name}-${var.environment}/cluster"
  retention_in_days = var.environment == "production" ? 90 : 30

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-logs"
  }
}

# CloudWatch Dashboard for ERP Monitoring
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EKS Cluster CPU Utilization"
          region = var.aws_region
          metrics = [
            ["AWS/EKS", "cluster_failed_node_count", "ClusterName", module.eks.cluster_name, { color = "#d62728", stat = "Maximum" }],
            [".", "cluster_node_count", ".", ".", { color = "#2ca02c", stat = "Average" }]
          ]
          period = 300
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Database Connections"
          region = var.aws_region
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", aws_rds_cluster.main.id, { color = "#1f77b4" }]
          ]
          period = 60
          annotations = {
            horizontal = [
              {
                value = 100
                label = "Warning"
                color = "#ff9900"
              },
              {
                value = 150
                label = "Critical"
                color = "#d62728"
              }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Application Load Balancer"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "app/${var.project_name}-alb", { stat = "Sum", period = 60 }],
            [".", "TargetResponseTime", ".", ".", { stat = "Average", yAxis = "right" }],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", { color = "#d62728", stat = "Sum" }],
            [".", "HTTPCode_Target_4XX_Count", ".", ".", { color = "#ff7f0e", stat = "Sum" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Redis Cache Performance"
          region = var.aws_region
          metrics = [
            ["AWS/ElastiCache", "CPUUtilization", "ReplicationGroupId", aws_elasticache_replication_group.main.id, { color = "#2ca02c" }],
            [".", "EngineCPUUtilization", ".", ".", { yAxis = "right" }],
            [".", "CacheHits", ".", ".", { stat = "Sum" }],
            [".", "CacheMisses", ".", ".", { stat = "Sum" }]
          ]
          period = 300
        }
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "high_database_connections" {
  alarm_name          = "${var.project_name}-${var.environment}-high-db-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  alarm_description   = "Database connections are high"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.id
  }
}

resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  alarm_name          = "${var.project_name}-${var.environment}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Cache CPU utilization is high"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 50
  alarm_description   = "High number of 5XX errors from ALB"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}

# SNS Topic for Alarms
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-${var.environment}-alarms"
}

# SES for Email Notifications
resource "aws_ses_email_identity" "notifications" {
  email = "alerts@${var.domain_name}"
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "geniinow.com"
}

# Outputs
output "cluster_autoscaler_role_arn" {
  value = module.cluster_autoscaler_irsa_role.iam_role_arn
}

output "lb_controller_role_arn" {
  value = module.load_balancer_controller_irsa_role.iam_role_arn
}

output "external_dns_role_arn" {
  value = module.external_dns_irsa_role.iam_role_arn
}
