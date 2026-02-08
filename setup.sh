#!/bin/bash
# Quick setup script for Genii ERP infrastructure
# Usage: ./setup.sh <environment>

set -e

ENVIRONMENT=${1:-production}
AWS_REGION=${AWS_REGION:-us-east-1}

echo "🚀 Genii ERP Infrastructure Setup"
echo "=================================="
echo "Environment: $ENVIRONMENT"
echo "AWS Region: $AWS_REGION"
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."

command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI is required but not installed. Aborting." >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform is required but not installed. Aborting." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required but not installed. Aborting." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "❌ jq is required but not installed. Aborting." >&2; exit 1; }

echo "✅ All prerequisites met"
echo ""

# Verify AWS credentials
echo "🔐 Verifying AWS credentials..."
aws sts get-caller-identity > /dev/null 2>&1 || {
  echo "❌ AWS credentials not configured. Please run 'aws configure'"
  exit 1
}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "✅ AWS credentials valid (Account: $ACCOUNT_ID)"
echo ""

# Create S3 bucket for Terraform state
echo "📦 Creating Terraform state bucket..."
STATE_BUCKET="genii-erp-terraform-state-${ACCOUNT_ID}"
if ! aws s3 ls "s3://${STATE_BUCKET}" 2>&1 > /dev/null; then
  aws s3 mb "s3://${STATE_BUCKET}" --region $AWS_REGION
  aws s3api put-bucket-versioning \
    --bucket $STATE_BUCKET \
    --versioning-configuration Status=Enabled
  echo "✅ Created state bucket: $STATE_BUCKET"
else
  echo "✅ State bucket already exists: $STATE_BUCKET"
fi
echo ""

# Create DynamoDB table for Terraform locks
echo "🔒 Creating Terraform locks table..."
LOCK_TABLE="terraform-locks"
if ! aws dynamodb describe-table --table-name $LOCK_TABLE 2>&1 > /dev/null; then
  aws dynamodb create-table \
    --table-name $LOCK_TABLE \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
  echo "✅ Created locks table: $LOCK_TABLE"
else
  echo "✅ Locks table already exists: $LOCK_TABLE"
fi
echo ""

# Deploy infrastructure
echo "🏗️  Deploying infrastructure..."
cd infrastructure/terraform

# Update backend configuration
cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket         = "${STATE_BUCKET}"
    key            = "infrastructure/terraform.tfstate"
    region         = "${AWS_REGION}"
    encrypt        = true
    dynamodb_table = "${LOCK_TABLE}"
  }
}
EOF

terraform init
terraform plan -var="environment=${ENVIRONMENT}" -out=tfplan

echo ""
echo "⚠️  Review the plan above. Do you want to apply? (yes/no)"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  terraform apply tfplan
else
  echo "❌ Infrastructure deployment cancelled"
  exit 1
fi

echo "✅ Infrastructure deployed"
echo ""

# Configure kubectl
echo "📡 Configuring kubectl..."
aws eks update-kubeconfig --name "genii-erp-${ENVIRONMENT}" --region $AWS_REGION
kubectl cluster-info
echo ""

# Deploy Kubernetes resources
echo "☸️  Deploying Kubernetes resources..."
cd ../..

# Create secrets template
echo ""
echo "🔐 Please enter the following secrets:"
read -sp 'Database URL: ' DB_URL
echo
read -sp 'Redis URL: ' REDIS_URL
echo
read -sp 'JWT Secret: ' JWT_SECRET
echo
read -sp 'Stripe Secret Key: ' STRIPE_KEY
echo
read -sp 'OpenAI API Key: ' OPENAI_KEY
echo

# Create Kubernetes secret
kubectl create secret generic genii-erp-secrets \
  --from-literal=database-url="$DB_URL" \
  --from-literal=redis-url="$REDIS_URL" \
  --from-literal=jwt-secret="$JWT_SECRET" \
  --from-literal=stripe-secret-key="$STRIPE_KEY" \
  --from-literal=openai-api-key="$OPENAI_KEY" \
  -n genii-erp --dry-run=client -o yaml | kubectl apply -f -

# Deploy manifests
kubectl apply -f kubernetes/

echo ""
echo "✅ Kubernetes resources deployed"
echo ""

# Wait for deployments
echo "⏳ Waiting for deployments to be ready..."
kubectl rollout status deployment/genii-erp-api -n genii-erp --timeout=300s
kubectl rollout status deployment/genii-ai-service -n genii-erp --timeout=300s
echo ""

# Run database migrations
echo "🗄️  Running database migrations..."
kubectl create job --from=cronjob/db-migration db-migration-setup -n genii-erp
kubectl wait --for=condition=complete job/db-migration-setup -n genii-erp --timeout=300s
echo "✅ Migrations completed"
echo ""

# Print summary
echo "🎉 Setup complete!"
echo "=================="
echo ""
echo "📊 Deployment Status:"
kubectl get pods -n genii-erp
echo ""
echo "🌐 Services:"
kubectl get svc -n genii-erp
echo ""
echo "🔗 Ingress:"
kubectl get ingress -n genii-erp
echo ""
echo "📖 Next steps:"
echo "   1. Configure DNS to point to the ALB"
echo "   2. Set up SSL certificates"
echo "   3. Run load tests: k6 run scripts/load-test.js"
echo "   4. Monitor dashboards at https://grafana.geniinow.com"
echo ""
echo "📚 Documentation:"
echo "   - Infrastructure: docs/INFRASTRUCTURE_PRD.md"
echo "   - API: docs/API_SPECIFICATION_PRD.md"
echo "   - Security: docs/SECURITY_COMPLIANCE_PRD.md"
echo ""
