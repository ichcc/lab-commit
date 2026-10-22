import http from "k6/http";
import { check } from "k6";

const target = __ENV.TARGET_URL || "https://lab-commit-task.lab.internal/";
const rate = Number(__ENV.TARGET_RPS || 40);

export const options = {
  insecureSkipTLSVerify: true,
  discardResponseBodies: false,
  scenarios: {
    ramp: {
      executor: "ramping-arrival-rate",
      startRate: 1,
      timeUnit: "1s",
      preAllocatedVUs: 20,
      maxVUs: 120,
      stages: [
        { target: rate, duration: __ENV.RAMP_UP || "2m" },
        { target: rate, duration: __ENV.HOLD || "6m" },
        { target: 0, duration: __ENV.RAMP_DOWN || "1m" },
      ],
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.05"],
    checks: ["rate>0.95"],
  },
};

export default function () {
  const res = http.get(target);
  check(res, {
    "status is 200": (r) => r.status === 200,
    "body has greeting": (r) => typeof r.body === "string" && r.body.startsWith("Hello Lab-Commit"),
  });
}
