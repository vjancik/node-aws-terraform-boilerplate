import http from 'k6/http';
import { check, sleep } from 'k6';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

// Target URL — set via K6_TARGET env var
if (!__ENV.K6_TARGET) throw new Error('K6_TARGET env var is required');
// Live dashboard — run with K6_WEB_DASHBOARD=true to open at http://localhost:5665
const TARGET = __ENV.K6_TARGET;

// Fibonacci n to compute — higher = more CPU load per request
// fib(40) ~= 500ms on a 256 CPU Fargate task
const FIB_N = __ENV.FIB_N || '30';

export const options = {
  stages: [
    { duration: '1m', target: 10 },   // ramp up to 10 VUs
    { duration: '2m',  target: 10 },   // hold — should trigger scale up
    { duration: '30s', target: 50 },   // ramp up to 50 VUs
    { duration: '2m',  target: 50 },   // hold — push harder
    { duration: '30s', target: 0 },    // ramp down
  ],
  thresholds: {
    http_req_failed:   ['rate<0.01'],   // <1% errors
    http_req_duration: ['p(95)<5000'],  // 95th percentile < 5s
  },
};

export default function () {
  const res = http.get(`${TARGET}/fib/${FIB_N}`);
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(0.1);
}

export function handleSummary(data) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filename = `scripts/load-testing/results/fib-${timestamp}.json`;

  return {
    stdout: textSummary(data, { indent: '  ', enableColors: true }),
    [filename]: JSON.stringify(data, null, 2),
  };
}
