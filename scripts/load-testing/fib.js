import http from 'k6/http';
import { check, sleep } from 'k6';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

// Target URL — set via K6_TARGET env var
if (!__ENV.K6_TARGET) throw new Error('K6_TARGET env var is required');
// Live dashboard — run with K6_WEB_DASHBOARD=true to open at http://localhost:5665
const TARGET = __ENV.K6_TARGET;

// fib(38) ~= 3-4s on 256 CPU — keeps tasks pegged at high CPU with fewer VUs.
// Override with FIB_N env var if needed.
const FIB_N = __ENV.FIB_N || '38';

// 30-minute run designed to observe autoscaling behaviour end-to-end.
//
// Timeline (approximate):
//   0:00 –  2:00  Warm-up ramp — light load, baseline latency
//   2:00 –  5:00  Ramp to full load — CPU climbs past 60% target, triggers scale-out
//   5:00 – 25:00  Sustained full load — watch new pods/tasks register, latency improve
//  25:00 – 27:00  Ramp down — CPU drops, scale-in cooldown begins
//  27:00 – 30:00  Idle hold — confirm scale-in fires
export const options = {
  stages: [
    { duration: '2m',  target: 5  },  // warm-up
    { duration: '3m',  target: 20 },  // ramp to full load
    { duration: '20m', target: 20 },  // hold — observe scale-out + stabilisation
    { duration: '2m',  target: 1  },  // ramp down
    { duration: '3m',  target: 0  },  // idle — observe scale-in
  ],
  thresholds: {
    http_req_failed:   ['rate<0.01'],    // <1% errors
    http_req_duration: ['p(95)<10000'],  // 95th percentile < 10s (generous: accounts for queue during scale-out)
  },
};

export default function () {
  const res = http.get(`${TARGET}/fib/${FIB_N}`);
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(0.5);
}

export function handleSummary(data) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filename = `scripts/load-testing/results/fib-${timestamp}.json`;

  return {
    stdout: textSummary(data, { indent: '  ', enableColors: true }),
    [filename]: JSON.stringify(data, null, 2),
  };
}
