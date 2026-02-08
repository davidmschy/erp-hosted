# Genii ERP Infrastructure PRD
## $100M Launch - Multi-Tenant SaaS ERP Platform

**Version:** 1.0  
**Date:** February 2026  
**Status:** In Development  

---

## 1. Executive Summary

This document defines the infrastructure architecture for Genii ERP's hosted platform, designed to support a $100M launch with 10,000+ concurrent users, multi-tenant isolation, AI integration, and enterprise-grade reliability.

### Key Objectives
- 99.99% uptime SLA
- Support for 10,000+ concurrent users at launch
- Sub-200ms API response times (p95)
- Multi-tenant data isolation with row-level security
- AI-powered features with token-based rate limiting
- PCI-DSS compliant billing infrastructure

---

## 2. Architecture Overview

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLIENT LAYER                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  Web App    │  │  Mobile App │  │   API Keys  │  │  Webhooks   │         │
│  │  (Next.js)  │  │  (React)    │  │  (Partners) │  │  (External) │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
└─────────┼────────────────┼────────────────┼────────────────┼────────────────┘
          │                │                │                │
          └────────────────┴────────────────┴────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │     CloudFlare (WAF/DDoS)   │
                    └──────────────┬──────────────┘
                                   │
┌──────────────────────────────────┴──────────────────────────────────────────┐
│                           INGRESS LAYER                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    AWS Application Load Balancer                     │   │
│  │         (SSL Termination, Geo-Routing, Rate Limiting)              │   │
│  └───────────────────────────────┬─────────────────────────────────────┘   │
└──────────────────────────────────┴──────────────────────────────────────────┘
                                   │
┌──────────────────────────────────┴──────────────────────────────────────────┐
│                         KUBERNETES CLUSTER (EKS)                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      NGINX Ingress Controller                        │   │
│  │              (Route-based routing, CORS, Rate Limits)               │   │
│  └───────────────────────────────┬─────────────────────────────────────┘   │
│                                  │                                          │
│  ┌───────────────────────────────┼─────────────────────────────────────┐  │
│  │       API SERVICES            │         AI SERVICES                 │  │
│  │  ┌─────────────────┐         │    ┌─────────────────┐              │  │
│  │  │  Genii ERP API  │         │    │  AI Gateway     │              │  │
│  │  │  (Node.js)      │◄────────┼────┤  (Rate Limit)   │              │  │
│  │  │  - Auth         │         │    │  - OpenAI       │              │  │
│  │  │  - Billing      │         │    │  - Anthropic    │              │  │
│  │  │  - Multi-tenant │         │    │  - Local LLMs   │              │  │
│  │  └─────────────────┘         │    └─────────────────┘              │  │
│  │           │                  │              │                       │  │
│  │           ▼                  │              ▼                       │  │
│  │  ┌─────────────────┐         │    ┌─────────────────┐              │  │
│  │  │  Background     │         │    │  Ollama         │              │  │
│  │  │  Workers        │         │    │  (Fallback)     │              │  │
│  │  └─────────────────┘         │    └─────────────────┘              │  │
│  └───────────────────────────────┴─────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                   │
┌──────────────────────────────────┴──────────────────────────────────────────┐
│                          DATA LAYER                                          │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐           │
│  │  Aurora PostgreSQL│  │  ElastiCache     │  │  S3 Buckets      │           │
│  │  (Multi-tenant)   │  │  Redis Cluster   │  │  Tenant Files    │           │
│  │  - Row-level sec  │  │  - Sessions      │  │  - Backups       │           │
│  │  - Read replicas  │  │  - Caching       │  │  - AI Models     │           │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘           │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Container Orchestration** | Amazon EKS (K8s 1.28+) | Container management, auto-scaling |
| **Compute** | EC2 (m6i/m5 instances) | Application workloads |
| **Database** | Aurora PostgreSQL 15 | Primary data store with row-level security |
| **Cache** | ElastiCache Redis 7 | Sessions, rate limiting, caching |
| **Object Storage** | S3 + CloudFront | Tenant files, assets, backups |
| **Queue** | Amazon SQS | Background job processing |
| **Monitoring** | Prometheus + Grafana + Loki | Metrics, logs, traces |
| **Secrets** | AWS Secrets Manager | Credential management |
| **CDN/WAF** | CloudFlare | DDoS protection, edge caching |

---

## 3. Multi-Tenant Architecture

### 3.1 Tenant Isolation Strategy

**Selected Approach:** Shared Database with Row-Level Security (RLS)

```sql
-- Tenant table
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subdomain VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    plan VARCHAR(50) DEFAULT 'basic',
    status VARCHAR(50) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT NOW()
);

-- Enable RLS on all tenant tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;

-- RLS Policy example
CREATE POLICY tenant_isolation_policy ON users
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

-- Set tenant context per request
SET app.current_tenant = 'tenant-uuid-from-jwt';
```

### 3.2 Tenant Data Segregation

| Aspect | Implementation |
|--------|---------------|
| **Database** | Single Aurora cluster, tenant_id column on all tables, RLS policies |
| **File Storage** | S3 prefix per tenant: `s3://bucket/tenants/{tenant_id}/...` |
| **Cache** | Redis key prefix: `tenant:{tenant_id}:...` |
| **Logs** | Tenant ID in structured logs, filtered in Loki |
| **API Keys** | Tenant-scoped JWTs with tenant_id claim |

### 3.3 Tenant Onboarding Flow

```
1. Sign-up → Create tenant record
2. Subdomain validation → Check uniqueness
3. Schema initialization → Run migrations for tenant
4. Default data seed → Create admin user, default settings
5. S3 bucket prefix → Create tenant folder structure
6. Cache warm → Pre-populate common data
7. Welcome email → Send credentials and onboarding guide
```

---

## 4. Scalability & Performance

### 4.1 Auto-Scaling Configuration

**Horizontal Pod Autoscaler (HPA):**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  minReplicas: 3
  maxReplicas: 50
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          averageUtilization: 70
          type: Utilization
    - type: Resource
      resource:
        name: memory
        target:
          averageUtilization: 80
          type: Utilization
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - type: Percent
          value: 100
          periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 10
          periodSeconds: 60
```

**Cluster Autoscaler:**
- Node group min: 2 nodes
- Node group max: 20 nodes
- Scale-up: When pods are unschedulable
- Scale-down: After 10 minutes of underutilization

### 4.2 Database Scaling

| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU > 70% | 5 minutes | Add read replica |
| Connections > 80% | Immediate | Connection pooling + alert |
| Storage > 80% | - | Auto-scaling enabled |
| Query time > 1s | - | Query optimization + index alert |

**Read Replica Strategy:**
- Writer: 1 instance (db.serverless)
- Readers: 2-5 instances (auto-scaled)
- Read/write splitting via PgBouncer

### 4.3 Caching Strategy

| Cache Type | TTL | Use Case |
|------------|-----|----------|
| Session | 24h | User authentication |
| API Response | 5m | Read-heavy endpoints |
| Tenant Config | 1h | Tenant settings |
| AI Tokens | 1m | Rate limit tracking |
| Inventory | 30s | Stock levels |

---

## 5. Security Architecture

### 5.1 Network Security

```
Internet → CloudFlare (WAF) → ALB → Nginx Ingress → Services

Security Layers:
1. CloudFlare: DDoS protection, Bot management, SSL
2. AWS WAF: SQL injection, XSS rules, rate limiting
3. Security Groups: Port restrictions, CIDR blocks
4. Network Policies: Pod-to-pod communication rules
5. mTLS: Service mesh between internal services
```

### 5.2 Data Security

| Layer | Implementation |
|-------|---------------|
| **Encryption at Rest** | AWS KMS for RDS, S3, EBS |
| **Encryption in Transit** | TLS 1.3 for all external, mTLS internal |
| **Secrets Management** | AWS Secrets Manager, rotated every 90 days |
| **PII Handling** | Tokenization for sensitive fields |
| **Backup Encryption** | KMS-encrypted S3 backups |

### 5.3 Compliance

- **PCI-DSS Level 1** (for Stripe integration)
- **SOC 2 Type II** (planned Q2 2026)
- **GDPR** data residency options
- **HIPAA** (future healthcare vertical)

---

## 6. Disaster Recovery

### 6.1 Backup Strategy

| Component | Frequency | Retention | Storage |
|-----------|-----------|-----------|---------|
| Database | Continuous + Daily snapshot | 35 days | Cross-region S3 |
| S3 Objects | Versioning enabled | 90 days | Cross-region replication |
| EKS Config | GitOps (Git backup) | Forever | GitHub + S3 |
| Secrets | Weekly export | 90 days | Encrypted S3 |

### 6.2 RTO/RPO

| Scenario | RTO | RPO |
|----------|-----|-----|
| Single AZ failure | 5 minutes | 0 (multi-AZ) |
| Regional failure | 30 minutes | 5 minutes (cross-region replication) |
| Database corruption | 15 minutes | 5 minutes (point-in-time recovery) |

### 6.3 Runbook: Regional Failover

```bash
# 1. Promote read replica in secondary region
aws rds promote-read-replica \
  --db-cluster-identifier genii-erp-dr-cluster \
  --region us-west-2

# 2. Update Route53 to point to DR ALB
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123456789 \
  --change-batch file://failover-route.json

# 3. Scale up DR EKS cluster
aws eks update-nodegroup-config \
  --cluster-name genii-erp-dr \
  --nodegroup-name general \
  --scaling-config minSize=3,maxSize=20,desiredSize=5
```

---

## 7. Monitoring & Alerting

### 7.1 Key Metrics

| Category | Metric | Warning | Critical |
|----------|--------|---------|----------|
| **Availability** | Uptime | - | < 99.9% |
| **Performance** | API p95 latency | > 200ms | > 500ms |
| **Performance** | DB query time | > 100ms | > 500ms |
| **Capacity** | CPU utilization | > 70% | > 90% |
| **Capacity** | Memory utilization | > 80% | > 95% |
| **Business** | Error rate | > 1% | > 5% |
| **Business** | Payment failures | > 2% | > 10% |

### 7.2 Alert Channels

| Severity | Channel | Response Time |
|----------|---------|---------------|
| Critical | PagerDuty + Slack + Email | 5 minutes |
| Warning | Slack + Email | 15 minutes |
| Info | Slack | Next business day |

---

## 8. Cost Estimates

### 8.1 Monthly Infrastructure Costs (Production)

| Component | Configuration | Monthly Cost |
|-----------|--------------|--------------|
| EKS Cluster | 1 cluster | $73 |
| EC2 (EKS nodes) | 5 x m6i.xlarge | $600 |
| Aurora PostgreSQL | Serverless v2 (avg 8 ACU) | $1,200 |
| ElastiCache Redis | r6g.xlarge cluster | $400 |
| ALB | 1 ALB + LCU | $100 |
| S3 | 1TB storage + requests | $50 |
| CloudFront | 10TB transfer | $400 |
| Data Transfer | Cross-AZ + Internet | $300 |
| CloudWatch | Logs + Metrics + Alarms | $200 |
| Secrets Manager | 50 secrets | $20 |
| **Total** | | **~$3,350/month** |

### 8.2 Scaling Cost Model

| Users | Monthly Cost | Key Drivers |
|-------|--------------|-------------|
| 1,000 | $3,500 | Base infrastructure |
| 5,000 | $6,000 | Additional nodes, DB ACU |
| 10,000 | $10,000 | Read replicas, cache cluster |
| 50,000 | $25,000 | Multi-region, dedicated nodes |

---

## 9. Implementation Timeline

| Week | Deliverables |
|------|-------------|
| **Week 1** | EKS cluster, VPC, Aurora PostgreSQL, Redis |
| **Week 2** | API deployment, Ingress, SSL, DNS |
| **Week 3** | AI service, OpenAI integration, local LLMs |
| **Week 4** | Monitoring, alerts, load testing, documentation |

---

## 10. Appendices

### A. Infrastructure Diagrams
- [Detailed Network Architecture](./diagrams/network.md)
- [Data Flow Diagram](./diagrams/data-flow.md)
- [Security Architecture](./diagrams/security.md)

### B. Runbooks
- [Database Failover](./runbooks/db-failover.md)
- [Scaling Procedures](./runbooks/scaling.md)
- [Incident Response](./runbooks/incident-response.md)

### C. Terraform Modules
- [EKS Module](./terraform/eks.tf)
- [Database Module](./terraform/database.tf)
- [Auto-scaling Module](./terraform/autoscaling.tf)
