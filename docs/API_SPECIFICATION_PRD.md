# Genii ERP API Specification PRD
## RESTful API Design for $100M Launch Platform

**Version:** 1.0  
**Base URL:** `https://api.geniinow.com/v1`  
**Date:** February 2026  

---

## 1. API Design Principles

### 1.1 Standards
- **RESTful architecture** with resource-oriented URLs
- **JSON** for request/response bodies
- **HTTPS only** - TLS 1.3 required
- **OAuth 2.0 + JWT** for authentication
- **OpenAPI 3.0** specification
- **Rate limiting** per tenant and per user

### 1.2 Common Response Format

```json
{
  "success": true,
  "data": { },
  "meta": {
    "timestamp": "2026-02-07T18:00:00Z",
    "request_id": "req_123456789",
    "tenant_id": "tenant_abc123"
  },
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 100,
    "total_pages": 5
  }
}
```

### 1.3 Error Response Format

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The request validation failed",
    "details": [
      {
        "field": "email",
        "message": "Invalid email format"
      }
    ],
    "request_id": "req_123456789"
  }
}
```

---

## 2. Authentication & Authorization

### 2.1 Authentication Methods

| Method | Use Case | Endpoint |
|--------|----------|----------|
| **OAuth 2.0** | User login, web apps | `/auth/oauth/authorize` |
| **API Keys** | Server-to-server, integrations | Header: `X-API-Key` |
| **JWT Bearer** | Authenticated requests | Header: `Authorization: Bearer {token}` |

### 2.2 JWT Token Structure

```json
{
  "header": {
    "alg": "RS256",
    "typ": "JWT",
    "kid": "key-2026-02"
  },
  "payload": {
    "sub": "user_uuid",
    "tenant_id": "tenant_uuid",
    "email": "user@example.com",
    "roles": ["admin", "user"],
    "permissions": ["invoices:read", "invoices:write"],
    "iat": 1707331200,
    "exp": 1707417600,
    "jti": "unique_token_id"
  }
}
```

### 2.3 Rate Limiting Headers

```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1707331260
X-RateLimit-Policy: 1000;w=60;comment="per minute"
```

---

## 3. Core Endpoints

### 3.1 Authentication

#### POST /auth/login
User login with email/password.

**Request:**
```json
{
  "email": "user@example.com",
  "password": "securePassword123",
  "tenant_subdomain": "acme-corp"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJSUzI1NiIs...",
    "refresh_token": "eyJhbGciOiJSUzI1NiIs...",
    "expires_in": 3600,
    "token_type": "Bearer",
    "user": {
      "id": "user_123",
      "email": "user@example.com",
      "name": "John Doe",
      "role": "admin"
    }
  }
}
```

#### POST /auth/refresh
Refresh access token.

**Request:**
```json
{
  "refresh_token": "eyJhbGciOiJSUzI1NiIs..."
}
```

#### POST /auth/logout
Invalidate tokens.

### 3.2 Tenants

#### GET /tenants/me
Get current tenant information.

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "tenant_abc123",
    "name": "Acme Corporation",
    "subdomain": "acme-corp",
    "plan": "enterprise",
    "status": "active",
    "settings": {
      "timezone": "America/New_York",
      "currency": "USD",
      "language": "en"
    },
    "limits": {
      "users": 100,
      "ai_tokens_per_month": 1000000,
      "storage_gb": 100
    },
    "usage": {
      "users": 45,
      "ai_tokens_this_month": 234000,
      "storage_used_gb": 23.5
    }
  }
}
```

#### PATCH /tenants/me/settings
Update tenant settings.

### 3.3 Users

#### GET /users
List users (paginated).

**Query Parameters:**
- `page` (int): Page number (default: 1)
- `per_page` (int): Items per page (default: 20, max: 100)
- `search` (string): Search by name or email
- `role` (string): Filter by role
- `status` (string): Filter by status

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "user_123",
      "email": "john@example.com",
      "name": "John Doe",
      "role": "admin",
      "status": "active",
      "last_login_at": "2026-02-07T15:30:00Z",
      "created_at": "2026-01-15T10:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 45,
    "total_pages": 3
  }
}
```

#### POST /users
Create new user.

**Request:**
```json
{
  "email": "jane@example.com",
  "name": "Jane Smith",
  "role": "user",
  "send_invite": true
}
```

#### GET /users/{id}
Get user details.

#### PATCH /users/{id}
Update user.

#### DELETE /users/{id}
Deactivate user.

### 3.4 Inventory Management

#### GET /inventory
List inventory items.

**Query Parameters:**
- `category` (string): Filter by category
- `low_stock` (boolean): Filter low stock items
- `search` (string): Search by name or SKU

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "inv_456",
      "sku": "SKU-001",
      "name": "Premium Widget",
      "description": "High-quality widget",
      "category": "widgets",
      "quantity_on_hand": 150,
      "quantity_reserved": 25,
      "quantity_available": 125,
      "reorder_point": 50,
      "reorder_quantity": 100,
      "unit_cost": 15.99,
      "unit_price": 29.99,
      "location": "Warehouse A",
      "status": "active",
      "created_at": "2026-01-10T08:00:00Z",
      "updated_at": "2026-02-05T14:30:00Z"
    }
  ]
}
```

#### POST /inventory
Create inventory item.

**Request:**
```json
{
  "sku": "SKU-002",
  "name": "Deluxe Gadget",
  "description": "Premium gadget with features",
  "category": "gadgets",
  "initial_quantity": 100,
  "unit_cost": 25.00,
  "unit_price": 49.99,
  "reorder_point": 30,
  "location": "Warehouse B"
}
```

#### POST /inventory/{id}/adjustments
Adjust inventory quantity.

**Request:**
```json
{
  "adjustment_type": "restock",
  "quantity": 50,
  "reason": "New shipment received",
  "reference": "PO-12345"
}
```

#### GET /inventory/{id}/movements
Get inventory movement history.

### 3.5 Invoices

#### GET /invoices
List invoices.

**Query Parameters:**
- `status` (string): draft, sent, paid, overdue, cancelled
- `customer_id` (string): Filter by customer
- `date_from` (date): Start date (YYYY-MM-DD)
- `date_to` (date): End date (YYYY-MM-DD)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "inv_789",
      "invoice_number": "INV-2026-001",
      "customer": {
        "id": "cust_123",
        "name": "TechCorp Inc.",
        "email": "billing@techcorp.com"
      },
      "status": "sent",
      "issue_date": "2026-02-01",
      "due_date": "2026-03-01",
      "subtotal": 5000.00,
      "tax_amount": 400.00,
      "total": 5400.00,
      "amount_paid": 0.00,
      "amount_due": 5400.00,
      "line_items": [
        {
          "id": "li_1",
          "description": "Consulting Services",
          "quantity": 40,
          "unit_price": 125.00,
          "total": 5000.00
        }
      ]
    }
  ]
}
```

#### POST /invoices
Create invoice.

**Request:**
```json
{
  "customer_id": "cust_123",
  "issue_date": "2026-02-07",
  "due_date": "2026-03-07",
  "line_items": [
    {
      "description": "Product Development",
      "quantity": 80,
      "unit_price": 150.00
    },
    {
      "description": "Design Services",
      "quantity": 20,
      "unit_price": 100.00
    }
  ],
  "tax_rate": 0.08,
  "notes": "Net 30 payment terms"
}
```

#### POST /invoices/{id}/send
Send invoice to customer.

#### POST /invoices/{id}/payments
Record payment.

**Request:**
```json
{
  "amount": 5400.00,
  "payment_method": "stripe",
  "stripe_payment_intent_id": "pi_123456789",
  "payment_date": "2026-02-10",
  "notes": "Paid via credit card"
}
```

### 3.6 AI Assistant

#### POST /ai/chat
Chat with AI assistant.

**Request:**
```json
{
  "message": "What are our top selling products this month?",
  "context": {
    "previous_messages": [],
    "screen": "dashboard"
  },
  "model": "gpt-4",
  "max_tokens": 500
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "message": "Based on your sales data for February 2026, your top selling products are:\n\n1. Premium Widget (SKU-001) - 450 units sold\n2. Deluxe Gadget (SKU-002) - 320 units sold\n3. Standard Tool (SKU-003) - 280 units sold\n\nThese products represent 65% of your total revenue this month.",
    "model_used": "gpt-4",
    "tokens_used": {
      "prompt": 45,
      "completion": 78,
      "total": 123
    },
    "citations": [
      {
        "type": "report",
        "id": "sales_report_feb_2026",
        "title": "February 2026 Sales Report"
      }
    ]
  },
  "meta": {
    "ai_request_id": "ai_req_789",
    "response_time_ms": 1450
  }
}
```

#### POST /ai/generate
Generate content with AI.

**Request:**
```json
{
  "task": "generate_invoice_email",
  "parameters": {
    "customer_name": "TechCorp Inc.",
    "invoice_number": "INV-2026-001",
    "amount": 5400.00,
    "due_date": "2026-03-01",
    "tone": "professional"
  }
}
```

#### GET /ai/usage
Get AI usage statistics.

**Response:**
```json
{
  "success": true,
  "data": {
    "period": "2026-02",
    "total_tokens": 245000,
    "total_requests": 1250,
    "models_used": {
      "gpt-4": { "tokens": 150000, "requests": 450 },
      "gpt-3.5-turbo": { "tokens": 95000, "requests": 800 }
    },
    "estimated_cost_usd": 18.50,
    "limit": 1000000,
    "percentage_used": 24.5
  }
}
```

### 3.7 Billing & Subscriptions

#### GET /billing/subscription
Get current subscription.

**Response:**
```json
{
  "success": true,
  "data": {
    "plan": "enterprise",
    "status": "active",
    "current_period_start": "2026-02-01T00:00:00Z",
    "current_period_end": "2026-03-01T00:00:00Z",
    "cancel_at_period_end": false,
    "payment_method": {
      "type": "card",
      "brand": "visa",
      "last4": "4242",
      "exp_month": 12,
      "exp_year": 2027
    },
    "upcoming_invoice": {
      "amount_due": 499.00,
      "due_date": "2026-03-01"
    }
  }
}
```

#### POST /billing/subscribe
Subscribe to a plan.

**Request:**
```json
{
  "plan": "enterprise",
  "payment_method_id": "pm_123456789",
  "billing_cycle": "monthly"
}
```

#### GET /billing/invoices
List billing invoices.

#### POST /billing/cancel
Cancel subscription.

---

## 4. Webhooks

### 4.1 Event Types

| Event | Description |
|-------|-------------|
| `invoice.created` | New invoice created |
| `invoice.paid` | Invoice payment received |
| `invoice.overdue` | Invoice past due date |
| `inventory.low_stock` | Item below reorder point |
| `user.invited` | New user invited |
| `ai.usage.threshold` | AI usage at 80% of limit |
| `subscription.canceled` | Subscription canceled |

### 4.2 Webhook Payload

```json
{
  "id": "evt_123456789",
  "type": "invoice.paid",
  "created_at": "2026-02-07T18:00:00Z",
  "data": {
    "invoice_id": "inv_789",
    "invoice_number": "INV-2026-001",
    "amount_paid": 5400.00,
    "payment_method": "card",
    "customer_id": "cust_123"
  }
}
```

### 4.3 Webhook Signature Verification

```javascript
const crypto = require('crypto');

function verifyWebhook(payload, signature, secret) {
  const expected = crypto
    .createHmac('sha256', secret)
    .update(payload, 'utf8')
    .digest('hex');
  return crypto.timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(expected)
  );
}
```

---

## 5. Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `UNAUTHORIZED` | 401 | Invalid or missing authentication |
| `FORBIDDEN` | 403 | Insufficient permissions |
| `NOT_FOUND` | 404 | Resource not found |
| `VALIDATION_ERROR` | 422 | Request validation failed |
| `RATE_LIMITED` | 429 | Too many requests |
| `INTERNAL_ERROR` | 500 | Server error |
| `SERVICE_UNAVAILABLE` | 503 | Service temporarily unavailable |
| `TENANT_SUSPENDED` | 403 | Tenant account suspended |
| `AI_QUOTA_EXCEEDED` | 429 | AI token limit reached |
| `PAYMENT_REQUIRED` | 402 | Payment required for action |

---

## 6. SDKs & Client Libraries

| Language | Package | Installation |
|----------|---------|--------------|
| JavaScript/Node.js | `@genii/erp-sdk` | `npm install @genii/erp-sdk` |
| Python | `genii-erp` | `pip install genii-erp` |
| Ruby | `genii_erp` | `gem install genii_erp` |
| PHP | `genii/erp-sdk` | `composer require genii/erp-sdk` |
| Go | `github.com/geniinow/go-sdk` | `go get github.com/geniinow/go-sdk` |

### JavaScript Example

```javascript
import { GeniiERP } from '@genii/erp-sdk';

const client = new GeniiERP({
  apiKey: 'sk_live_...',
  tenantSubdomain: 'acme-corp'
});

// Get invoices
const invoices = await client.invoices.list({
  status: 'overdue',
  page: 1,
  per_page: 20
});

// Create invoice
const invoice = await client.invoices.create({
  customerId: 'cust_123',
  lineItems: [
    { description: 'Services', quantity: 10, unitPrice: 100 }
  ]
});
```

---

## 7. API Versioning

- Current version: `v1`
- Version in URL: `/v1/...`
- Deprecation headers for endpoints:
  ```
  Sunset: Sat, 01 Jun 2026 00:00:00 GMT
  Deprecation: true
  ```

---

## 8. OpenAPI Specification

Full OpenAPI 3.0 spec available at:
- JSON: `https://api.geniinow.com/v1/openapi.json`
- YAML: `https://api.geniinow.com/v1/openapi.yaml`
- Documentation: `https://docs.geniinow.com/api`
