# Multi-Tenant Database Schema

This directory contains SQL migrations for the Genii ERP multi-tenant database.

## Schema Overview

### Tenant Isolation
- Row-Level Security (RLS) enabled on all tables
- `tenant_id` column on every table
- Tenant context set per request

### Core Tables

#### tenants
```sql
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subdomain VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    plan VARCHAR(50) DEFAULT 'basic',
    status VARCHAR(50) DEFAULT 'active',
    settings JSONB DEFAULT '{}',
    limits JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

#### users
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    email VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255),
    role VARCHAR(50) DEFAULT 'user',
    status VARCHAR(50) DEFAULT 'active',
    mfa_enabled BOOLEAN DEFAULT FALSE,
    mfa_secret VARCHAR(255),
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(tenant_id, email)
);

-- Enable RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- RLS Policy
CREATE POLICY tenant_isolation ON users
    USING (tenant_id = current_setting('app.current_tenant')::UUID);
```

#### inventory
```sql
CREATE TABLE inventory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    sku VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100),
    quantity_on_hand INTEGER DEFAULT 0,
    quantity_reserved INTEGER DEFAULT 0,
    quantity_available INTEGER GENERATED ALWAYS AS (quantity_on_hand - quantity_reserved) STORED,
    reorder_point INTEGER DEFAULT 0,
    reorder_quantity INTEGER DEFAULT 0,
    unit_cost DECIMAL(12,2),
    unit_price DECIMAL(12,2),
    location VARCHAR(255),
    status VARCHAR(50) DEFAULT 'active',
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(tenant_id, sku)
);

ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON inventory
    USING (tenant_id = current_setting('app.current_tenant')::UUID);
```

#### invoices
```sql
CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    invoice_number VARCHAR(100) NOT NULL,
    customer_id UUID NOT NULL,
    customer_name VARCHAR(255),
    customer_email VARCHAR(255),
    status VARCHAR(50) DEFAULT 'draft',
    issue_date DATE,
    due_date DATE,
    subtotal DECIMAL(12,2) DEFAULT 0,
    tax_rate DECIMAL(5,4) DEFAULT 0,
    tax_amount DECIMAL(12,2) DEFAULT 0,
    total DECIMAL(12,2) DEFAULT 0,
    amount_paid DECIMAL(12,2) DEFAULT 0,
    amount_due DECIMAL(12,2) GENERATED ALWAYS AS (total - amount_paid) STORED,
    notes TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(tenant_id, invoice_number)
);

ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON invoices
    USING (tenant_id = current_setting('app.current_tenant')::UUID);
```

#### invoice_line_items
```sql
CREATE TABLE invoice_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    invoice_id UUID REFERENCES invoices(id) ON DELETE CASCADE,
    description TEXT NOT NULL,
    quantity DECIMAL(10,2) DEFAULT 1,
    unit_price DECIMAL(12,2) DEFAULT 0,
    total DECIMAL(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW()
);

ALTER TABLE invoice_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON invoice_line_items
    USING (tenant_id = current_setting('app.current_tenant')::UUID);
```

#### ai_usage
```sql
CREATE TABLE ai_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    user_id UUID REFERENCES users(id),
    request_type VARCHAR(100),
    model VARCHAR(100),
    prompt_tokens INTEGER DEFAULT 0,
    completion_tokens INTEGER DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    cost_usd DECIMAL(10,6),
    latency_ms INTEGER,
    success BOOLEAN DEFAULT TRUE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW()
);

ALTER TABLE ai_usage ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON ai_usage
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

-- Indexes for reporting
CREATE INDEX idx_ai_usage_tenant_created ON ai_usage(tenant_id, created_at);
CREATE INDEX idx_ai_usage_tenant_month ON ai_usage(tenant_id, DATE_TRUNC('month', created_at));
```

#### audit_logs
```sql
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    severity VARCHAR(20) DEFAULT 'info',
    actor_id UUID,
    actor_type VARCHAR(50) DEFAULT 'user',
    actor_email VARCHAR(255),
    actor_ip INET,
    resource_type VARCHAR(100),
    resource_id UUID,
    action VARCHAR(50),
    status VARCHAR(50),
    changes JSONB,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

-- No RLS on audit logs for compliance visibility
CREATE INDEX idx_audit_logs_tenant_created ON audit_logs(tenant_id, created_at);
CREATE INDEX idx_audit_logs_event_type ON audit_logs(event_type);
CREATE INDEX idx_audit_logs_actor ON audit_logs(actor_id);
```

## Migrations

### Running Migrations

```bash
# Using Node.js
npm run migrate

# Using kubectl job
kubectl create job --from=cronjob/db-migration migration-$(date +%s) -n genii-erp

# Using Flyway
flyway migrate -url=jdbc:postgresql://host:5432/genii_erp -user=admin -password=xxx
```

## Functions and Triggers

### Set Tenant Context
```sql
CREATE OR REPLACE FUNCTION set_tenant_context(tenant_uuid UUID)
RETURNS VOID AS $$
BEGIN
    PERFORM set_config('app.current_tenant', tenant_uuid::text, false);
END;
$$ LANGUAGE plpgsql;
```

### Updated At Trigger
```sql
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();
```
