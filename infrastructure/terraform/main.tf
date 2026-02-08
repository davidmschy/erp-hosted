{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "elasticloadbalancing:*",
        "cloudwatch:*",
        "autoscaling:*",
        "iam:CreateServiceLinkedRole",
        "eks:*",
        "logs:*",
        "kms:*",
        "rds:*",
        "elasticache:*",
        "s3:*",
        "sqs:*",
        "sns:*",
        "secretsmanager:*"
      ],
      "Resource": "*"
    }
  ]
}
