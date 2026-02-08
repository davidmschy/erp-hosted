import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const apiLatency = new Trend('api_latency');
const aiLatency = new Trend('ai_latency');

export const options = {
  stages: [
    // Warm up
    { duration: '2m', target: 100 },
    // Steady load
    { duration: '5m', target: 100 },
    // Ramp up
    { duration: '3m', target: 1000 },
    // Peak load
    { duration: '10m', target: 10000 },
    // Sustained peak
    { duration: '10m', target: 10000 },
    // Ramp down
    { duration: '5m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<200'],
    http_req_failed: ['rate<0.01'],
    errors: ['rate<0.05'],
    api_latency: ['p(95)<500'],
    ai_latency: ['p(95)<3000'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'https://api.geniinow.com/v1';
const API_KEY = __ENV.API_KEY || 'test-key';

export function setup() {
  // Authenticate and get token
  const loginRes = http.post(`${BASE_URL}/auth/login`, JSON.stringify({
    email: 'loadtest@geniinow.com',
    password: 'loadtest123',
    tenant_subdomain: 'loadtest',
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
  
  check(loginRes, {
    'login successful': (r) => r.status === 200,
  });
  
  const token = loginRes.json('data.access_token');
  return { token };
}

export default function (data) {
  const headers = {
    'Authorization': `Bearer ${data.token}`,
    'Content-Type': 'application/json',
    'X-Tenant-ID': 'loadtest-tenant',
  };

  group('Health Check', () => {
    const res = http.get(`${BASE_URL}/health`, { headers });
    const success = check(res, {
      'health check status is 200': (r) => r.status === 200,
      'health check response time < 100ms': (r) => r.timings.duration < 100,
    });
    errorRate.add(!success);
    apiLatency.add(res.timings.duration);
  });

  group('User Operations', () => {
    // Get current user
    const userRes = http.get(`${BASE_URL}/users/me`, { headers });
    check(userRes, {
      'get user status is 200': (r) => r.status === 200,
    });
    apiLatency.add(userRes.timings.duration);
    sleep(1);
  });

  group('Inventory Operations', () => {
    // List inventory
    const listRes = http.get(`${BASE_URL}/inventory?page=1&per_page=20`, { headers });
    check(listRes, {
      'list inventory status is 200': (r) => r.status === 200,
      'inventory loads in < 200ms': (r) => r.timings.duration < 200,
    });
    apiLatency.add(listRes.timings.duration);
    sleep(2);

    // Create inventory item (10% of requests)
    if (Math.random() < 0.1) {
      const createRes = http.post(`${BASE_URL}/inventory`, JSON.stringify({
        sku: `SKU-${Date.now()}-${__VU}`,
        name: `Test Product ${__VU}`,
        description: 'Load test product',
        category: 'test',
        initial_quantity: 100,
        unit_cost: 10.00,
        unit_price: 20.00,
      }), { headers });
      
      check(createRes, {
        'create inventory status is 201': (r) => r.status === 201,
      });
      apiLatency.add(createRes.timings.duration);
    }
  });

  group('Invoice Operations', () => {
    // List invoices
    const listRes = http.get(`${BASE_URL}/invoices?page=1&per_page=20`, { headers });
    check(listRes, {
      'list invoices status is 200': (r) => r.status === 200,
    });
    apiLatency.add(listRes.timings.duration);
    sleep(2);

    // Create invoice (5% of requests)
    if (Math.random() < 0.05) {
      const createRes = http.post(`${BASE_URL}/invoices`, JSON.stringify({
        customer_id: 'cust_loadtest',
        line_items: [
          { description: 'Load Test Service', quantity: 1, unit_price: 100.00 },
        ],
        tax_rate: 0.08,
      }), { headers });
      
      check(createRes, {
        'create invoice status is 201': (r) => r.status === 201,
      });
      apiLatency.add(createRes.timings.duration);
    }
  });

  group('AI Operations', () => {
    // AI chat (1% of requests due to cost)
    if (Math.random() < 0.01) {
      const aiRes = http.post(`${BASE_URL}/ai/chat`, JSON.stringify({
        message: 'What are my top selling products?',
        model: 'gpt-3.5-turbo',
        max_tokens: 150,
      }), { headers });
      
      check(aiRes, {
        'AI response status is 200': (r) => r.status === 200,
        'AI response time < 5s': (r) => r.timings.duration < 5000,
      });
      aiLatency.add(aiRes.timings.duration);
    }
  });

  sleep(1);
}

export function teardown(data) {
  // Cleanup test data
  const headers = {
    'Authorization': `Bearer ${data.token}`,
    'Content-Type': 'application/json',
  };
  
  http.del(`${BASE_URL}/loadtest/cleanup`, null, { headers });
}
