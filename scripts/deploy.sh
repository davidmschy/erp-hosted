#!/bin/bash
# Deploy script for Genii ERP infrastructure

set -e

ENVIRONMENT=${1:-production}
AWS_REGION=${AWS_REGION:-us-east-1}
CLUSTER_NAME="genii-erp-${ENVIRONMENT}"

echo "🚀 Deploying Genii ERP to ${ENVIRONMENT}..."

# Verify AWS credentials
aws sts get-caller-identity > /dev/null 2>&1 || {
  echo "❌ AWS credentials not configured"
  exit 1
}

# Update kubeconfig
echo "📡 Configuring kubectl..."
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}

# Verify cluster connection
kubectl cluster-info > /dev/null 2>&1 || {
  echo "❌ Failed to connect to EKS cluster"
  exit 1
}

# Create namespaces
echo "📁 Creating namespaces..."
kubectl apply -f kubernetes/namespaces.yaml

# Apply secrets (ensure these exist)
echo "🔐 Verifying secrets..."
kubectl get secret genii-erp-secrets -n genii-erp > /dev/null 2>&1 || {
  echo "⚠️  Secrets not found. Please create secrets first:"
  echo "   kubectl create secret generic genii-erp-secrets \\"
  echo "     --from-literal=database-url='...' \\"
  echo "     --from-literal=redis-url='...' \\"
  echo "     --from-literal=jwt-secret='...' \\"
  echo "     --from-literal=stripe-secret-key='...' \\"
  echo "     --from-literal=openai-api-key='...' \\"
  echo "     -n genii-erp"
  exit 1
}

# Deploy core services
echo "🚢 Deploying API services..."
kubectl apply -f kubernetes/api-deployment.yaml

# Deploy AI services
echo "🤖 Deploying AI services..."
kubectl apply -f kubernetes/ai-service.yaml

# Deploy ingress
echo "🌐 Deploying ingress..."
kubectl apply -f kubernetes/ingress.yaml

# Deploy jobs
echo "📋 Deploying cronjobs..."
kubectl apply -f kubernetes/jobs.yaml

# Deploy monitoring (optional)
if [ "${DEPLOY_MONITORING}" = "true" ]; then
  echo "📊 Deploying monitoring..."
  kubectl apply -f kubernetes/monitoring.yaml
fi

# Wait for deployments
echo "⏳ Waiting for deployments to be ready..."
kubectl rollout status deployment/genii-erp-api -n genii-erp --timeout=300s
kubectl rollout status deployment/genii-ai-service -n genii-erp --timeout=300s

# Run health check
echo "🏥 Running health checks..."
sleep 10

HEALTH_STATUS=$(kubectl get pods -n genii-erp -l app=genii-erp-api -o jsonpath='{.items[0].status.phase}')
if [ "$HEALTH_STATUS" != "Running" ]; then
  echo "❌ API pods not healthy"
  kubectl get pods -n genii-erp
  exit 1
fi

echo "✅ Deployment complete!"
echo ""
echo "📊 Deployment Status:"
kubectl get pods -n genii-erp
echo ""
echo "🌐 Services:"
kubectl get svc -n genii-erp
echo ""
echo "🔗 Ingress:"
kubectl get ingress -n genii-erp
