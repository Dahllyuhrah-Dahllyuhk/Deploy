/**
 * matuabom 부하 테스트 스크립트
 *
 * 실행 방법:
 *   docker run --rm -i --network host grafana/k6 run - < k6/scripts/load-test.js
 *
 * Prometheus + Grafana 연동 실행 (메트릭 전송):
 *   docker run --rm -i --network host \
 *     -e K6_PROMETHEUS_RW_SERVER_URL=http://localhost:9090/api/v1/write \
 *     grafana/k6 run --out experimental-prometheus-rw - < k6/scripts/load-test.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// ── 커스텀 메트릭 ────────────────────────────────────────────────────
const errorRate = new Rate('errors');
const meetingDuration = new Trend('meeting_api_duration');

// ── 테스트 시나리오 ──────────────────────────────────────────────────
export const options = {
  scenarios: {
    // 1단계: 점진적 워밍업
    ramp_up: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 10 },   // 0 → 10 VU (워밍업)
        { duration: '1m',  target: 30 },   // 10 → 30 VU (부하 증가)
        { duration: '2m',  target: 30 },   // 30 VU 유지
        { duration: '30s', target: 0 },    // 쿨다운
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    // 성공 기준
    http_req_failed:        ['rate<0.05'],         // 에러율 5% 미만
    http_req_duration:      ['p(95)<500'],         // 95%ile 500ms 미만
    meeting_api_duration:   ['p(99)<1000'],        // 99%ile 1s 미만
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// ── 헬스체크 (인증 불필요) ────────────────────────────────────────────
export default function () {
  // 1. 헬스체크
  const healthRes = http.get(`${BASE_URL}/actuator/health`);
  check(healthRes, {
    'health status 200': (r) => r.status === 200,
    'health UP': (r) => JSON.parse(r.body).status === 'UP',
  });
  errorRate.add(healthRes.status !== 200);

  sleep(0.5);

  // 2. 미인증 엔드포인트 (401 예상 — 응답 시간 측정 목적)
  const meetingsRes = http.get(`${BASE_URL}/api/meetings`, {
    tags: { name: 'GET /api/meetings' },
  });
  meetingDuration.add(meetingsRes.timings.duration);
  check(meetingsRes, {
    'meetings responds': (r) => r.status === 200 || r.status === 401 || r.status === 403,
  });

  sleep(1);
}

// ── 테스트 종료 후 요약 출력 ──────────────────────────────────────────
export function handleSummary(data) {
  return {
    stdout: JSON.stringify({
      total_requests:  data.metrics.http_reqs?.values?.count,
      error_rate:      data.metrics.http_req_failed?.values?.rate,
      p95_duration_ms: data.metrics.http_req_duration?.values?.['p(95)'],
      p99_duration_ms: data.metrics.http_req_duration?.values?.['p(99)'],
    }, null, 2),
  };
}
