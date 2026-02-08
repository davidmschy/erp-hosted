# Genii ERP - Hosted Infrastructure

[![CI/CD](https://github.com/geniinow/erp-hosted/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/geniinow/erp-hosted/actions)
[![Infrastructure](https://github.com/geniinow/erp-hosted/actions/workflows/infrastructure.yml/badge.svg)](https://github.com/geniinow/erp-hosted/actions)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Enterprise-grade multi-tenant ERP platform with AI integration, built for scale.

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/geniinow/erp-hosted.git
cd erp-hosted

# Set up AWS credentials
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret

# Deploy infrastructure
cd infrastructure/terraform
terraform init
terraform plan
terraform apply

# Deploy to Kubernetes
aws eks update-kubeconfig --name genii-erp-production
kubectl apply -f ../../kubernetes/
```

## 📋 Documentation

- [Infrastructure PRD](docs/INFRASTRUCTURE_PRD.md) - Architecture and design
- [API Specification](docs/API_SPECIFICATION_PRD.md) - REST API documentation
- [Security & Compliance](docs/SECURITY_COMPLIANCE_PRD.md) - Security architecture
- [Launch Checklist](docs/LAUNCH_CHECKLIST_PRD.md) - Go-live preparation

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Client Layer (Web, Mobile, API)                            │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│  CloudFlare (WAF, DDoS Protection, CDN)                     │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│  AWS Application Load Balancer                              │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│  Amazon EKS (Kubernetes 1.28+)                              │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │  ERP API    │ │  AI Service │ │  Web App    │           │
│  │  (Node.js)  │ │  (Python)   │ │  (Next.js)  │           │
│  └─────────────┘ └─────────────┘ └─────────────┘           │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│  Data Layer                                                 │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │  Aurora     │ │  ElastiCache│ │  S3         │           │
│  │  PostgreSQL │ │  Redis      │ │  Storage    │           │
│  │  (Multi-AZ) │ │  (Cluster)  │ │  (Encrypted)│           │
│  └─────────────┘ └─────────────┘ └─────────────┘           │
└─────────────────────────────────────────────────────────────┘
```

## 🛠️ Infrastructure Components

### Week 1: Foundation
- [x] Kubernetes cluster (EKS) with auto-scaling
- [x] Multi-tenant Aurora PostgreSQL database
- [x] Redis cluster for caching and sessions
- [x] CI/CD pipeline with GitHub Actions
- [x] Terraform infrastructure as code

### Week 2: Core ERP
- [x] API deployment with ingress
- [x] Rate limiting and API gateway
- [x] Stripe billing integration
- [x] JWT authentication with tenant isolation

### Week 3: AI Integration
- [x] OpenAI API integration
- [x] Token usage tracking per tenant
- [x] AI agent connector
- [x] Local LLM fallback (Ollama)

### Week 4: Launch Ready
- [x] Load testing scripts (k6)
- [x] Monitoring (Prometheus + Grafana)
- [x] Alerting and incident response
- [x] Complete documentation

## 🔒 Security

- TLS 1.3 everywhere
- mTLS between services
- Row-level security in PostgreSQL
- AWS KMS encryption
- SOC 2 Type II compliance roadmap
- PCI-DSS Level 1 for payments

## 📊 Monitoring

- **Metrics:** Prometheus + Grafana
- **Logs:** Loki + Grafana
- **Traces:** Tempo + Grafana
- **APM:** Built-in application metrics
- **Uptime:** Pinger + Status Page

## 🧪 Testing

```bash
# Unit tests
npm test

# Integration tests
npm run test:integration

# Load tests
k6 run scripts/load-test.js

# Security scan
trivy fs .
```

## 🚢 Deployment

### Production Deployment

```bash
# 1. Merge to main triggers CI/CD
# 2. Automated tests run
# 3. Docker images built and pushed to ECR
# 4. Database migrations applied
# 5. Canary deployment (20% traffic)
# 6. Smoke tests
# 7. Full rollout
```

### Database Migrations

```bash
# Run migrations
kubectl create job --from=cronjob/db-migration migration-$(date +%s) -n genii-erp

# Check migration status
kubectl logs -l job-name=migration-xxx -n genii-erp
```

## 📈 Scaling

| Users | Nodes | DB ACU | Cache |
|-------|-------|--------|-------|
| 1,000 | 3 | 4 | 1 |
| 5,000 | 5 | 8 | 2 |
| 10,000 | 10 | 16 | 3 |
| 50,000 | 25 | 32 | 5 |

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing`)
5. Open a Pull Request

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🆘 Support

- Documentation: https://docs.geniinow.com
- API Reference: https://api.geniinow.com/v1
- Status: https://status.geniinow.com
- Email: support@geniinow.com

---

Built with ❤️ by the Genii Team
