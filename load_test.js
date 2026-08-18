#!/usr/bin/env bun
/**
 * LEP Load Test — Bun Edition
 * ============================
 * Uses Bun's native fetch (no npm packages needed).
 *
 * Usage:
 *   bun load_test.js                            # 20 VUs, 60s
 *   bun load_test.js --vu 50 --duration 120     # 50 VUs, 2 min
 *   bun load_test.js --vu 100 --duration 300    # 100 VUs stress
 *   bun load_test.js --url https://custom.com   # custom target
 */

// ──────────────────────────────────────────────────────────────────
// ANSI colours
// ──────────────────────────────────────────────────────────────────
const R = "\x1b[0m";
const BOLD   = "\x1b[1m";
const DIM    = "\x1b[2m";
const RED    = "\x1b[91m";
const GREEN  = "\x1b[92m";
const YELLOW = "\x1b[93m";
const CYAN   = "\x1b[96m";
const WHITE  = "\x1b[97m";

const c = (col, txt) => `${col}${txt}${R}`;

// ──────────────────────────────────────────────────────────────────
// CLI args
// ──────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const arg  = (flag, def) => {
  const i = argv.indexOf(flag);
  return i !== -1 ? argv[i + 1] : def;
};

const BASE_URL  = arg("--url",      "https://nagaland.lep.2026.vibha.org");
const VU_COUNT  = parseInt(arg("--vu",       "20"),  10);
const DURATION  = parseInt(arg("--duration", "60"),  10);   // seconds
const THINK     = parseFloat(arg("--think",  "1.5"));       // seconds avg
const RAMP_SEC  = parseInt(arg("--ramp",     "10"),  10);   // seconds

// ──────────────────────────────────────────────────────────────────
// Scenarios — weighted, realistic teacher-browsing pattern
// ──────────────────────────────────────────────────────────────────
const rand   = (arr) => arr[Math.floor(Math.random() * arr.length)];
const DISTS  = [1, 2, 3, 4, 5];
const BLOCKS = [1, 2, 3, 4, 5, 6, 7, 8];
const GRADES = [1, 2, 3, 4, 5];
const PROJS  = [1, 2, 3];

const SCENARIOS = [
  { name: "Homepage",      weight: 30, path: () => "/" },
  { name: "Blocks AJAX",   weight: 15, path: () => `/ajax/blocks?district_id=${rand(DISTS)}` },
  { name: "Schools AJAX",  weight: 15, path: () => `/ajax/schools?block_id=${rand(BLOCKS)}` },
  { name: "Subjects AJAX", weight: 15, path: () => `/ajax/subjects?grade_id=${rand(GRADES)}` },
  { name: "Project AJAX",  weight: 15, path: () => `/ajax/project?grade_id=${rand(GRADES)}&cycle_id=1` },
  { name: "PDF Download",  weight: 10, path: () => `/projects/${rand(PROJS)}/download` },
];

const TOTAL_WEIGHT = SCENARIOS.reduce((s, sc) => s + sc.weight, 0);

function pickScenario() {
  let r = Math.random() * TOTAL_WEIGHT;
  for (const sc of SCENARIOS) {
    r -= sc.weight;
    if (r <= 0) return sc;
  }
  return SCENARIOS.at(-1);
}

// ──────────────────────────────────────────────────────────────────
// Shared state
// ──────────────────────────────────────────────────────────────────
const results  = [];   // { name, latencyMs, status, error, ts }
const redirectHosts = new Map();   // hostname -> count, from PDF redirect Location headers
let   stopped  = false;
let   startTs  = 0;

function record(r) { results.push(r); }

function hostOf(u) {
  try { return new URL(u).hostname; } catch { return "unparseable"; }
}

function isLoopbackOrPrivate(hostname) {
  if (!hostname) return false;
  if (hostname === "127.0.0.1" || hostname === "localhost" || hostname === "::1") return true;
  if (/^10\.\d+\.\d+\.\d+$/.test(hostname)) return true;
  if (/^192\.168\.\d+\.\d+$/.test(hostname)) return true;
  if (/^172\.(1[6-9]|2\d|3[0-1])\.\d+\.\d+$/.test(hostname)) return true;
  return false;
}

// ──────────────────────────────────────────────────────────────────
// Sleep helper
// ──────────────────────────────────────────────────────────────────
const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// ──────────────────────────────────────────────────────────────────
// Virtual User
// ──────────────────────────────────────────────────────────────────
const COMMON_HEADERS = {
  "User-Agent":      "LEP-LoadTest/2.0 (Bun; perf-baseline)",
  "Accept":          "text/html,application/json,*/*",
  "Accept-Encoding": "gzip, deflate",
  "Accept-Language": "en-IN,en;q=0.9",
};

async function fetchTimed(url, { redirect = "follow", timeoutMs = 30_000 } = {}) {
  const t0 = performance.now();
  let status = 0, error = null, location = null;

  try {
    const res = await fetch(url, {
      method: "GET",
      redirect,
      headers: COMMON_HEADERS,
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (redirect === "manual" && res.status >= 300 && res.status < 400) {
      location = res.headers.get("location");
    } else {
      await res.arrayBuffer(); // consume body for accurate end-to-end timing
    }
    status = res.status;
  } catch (e) {
    error = e.name === "TimeoutError" ? "TIMEOUT" : `ERR: ${e.name}`;
  }

  return { latencyMs: performance.now() - t0, status, error, location };
}

async function virtualUser(id) {
  while (!stopped) {
    const sc   = pickScenario();
    const path = sc.path();
    const url  = BASE_URL + path;

    if (sc.name === "PDF Download") {
      // Phase 1: Laravel's own work only (DB lookup + signed-URL generation +
      // the 302 itself) — redirect:"manual" so MinIO's transfer time is never
      // blended into this number.
      const r1 = await fetchTimed(url, { redirect: "manual", timeoutMs: 15_000 });
      record({
        name: "PDF: Laravel redirect",
        latencyMs: r1.latencyMs, status: r1.status, error: r1.error,
        ts: Date.now() / 1000,
      });

      if (r1.location) {
        const target = new URL(r1.location, url).href;
        const host   = hostOf(target);
        redirectHosts.set(host, (redirectHosts.get(host) ?? 0) + 1);

        // Phase 2: the actual file transfer, timed separately from Laravel.
        const r2 = await fetchTimed(target, { redirect: "follow", timeoutMs: 30_000 });
        record({
          name: "PDF: MinIO transfer",
          latencyMs: r2.latencyMs, status: r2.status, error: r2.error,
          ts: Date.now() / 1000,
        });
      }
    } else {
      const r = await fetchTimed(url, { redirect: "follow", timeoutMs: 30_000 });
      record({ name: sc.name, latencyMs: r.latencyMs, status: r.status, error: r.error, ts: Date.now() / 1000 });
    }

    // Think time with jitter (0.5× – 1.5× of mean)
    if (!stopped) {
      const jitter = THINK * 1000 * (0.5 + Math.random());
      await sleep(jitter);
    }
  }
}

// ──────────────────────────────────────────────────────────────────
// Live progress bar (printed every 2 s)
// ──────────────────────────────────────────────────────────────────
let lastCount = 0;

function printProgress() {
  const elapsed  = (Date.now() / 1000) - startTs;
  const total    = results.length;
  const recent   = total - lastCount;
  const rps      = recent / 2;
  lastCount      = total;

  const errors   = results.filter(r => r.error || r.status >= 500).length;
  const errPct   = total ? (errors / total * 100) : 0;

  const latLast  = results.slice(-100)
    .filter(r => !r.error)
    .map(r => r.latencyMs)
    .sort((a, b) => a - b);
  const p95      = latLast.length >= 2
    ? latLast[Math.floor(latLast.length * 0.95)]
    : 0;

  const remaining = Math.max(0, DURATION - elapsed);
  const barLen    = 28;
  const filled    = Math.min(barLen, Math.floor(barLen * elapsed / DURATION));
  const bar       = "█".repeat(filled) + "░".repeat(barLen - filled);

  const errCol = errPct < 1 ? GREEN : errPct < 5 ? YELLOW : RED;

  process.stdout.write(
    `\r  ${c(CYAN, `[${bar}]`)} ` +
    `${c(WHITE, `${elapsed.toFixed(0)}s`)}/${DURATION}s  ` +
    `VUs:${c(BOLD, String(VU_COUNT))}  ` +
    `Reqs:${c(BOLD, String(total))}  ` +
    `RPS:${c(GREEN, rps.toFixed(1))}  ` +
    `P95:${c(YELLOW, `${p95.toFixed(0)}ms`)}  ` +
    `Err:${c(errCol, `${errPct.toFixed(1)}%`)}  ` +
    `Left:${c(DIM, `${remaining.toFixed(0)}s`)}`
  );
}

// ──────────────────────────────────────────────────────────────────
// Stats helpers
// ──────────────────────────────────────────────────────────────────
function pct(sorted, p) {
  if (!sorted.length) return 0;
  const i = Math.floor(sorted.length * p / 100);
  return sorted[Math.min(i, sorted.length - 1)];
}

function mean(arr) {
  return arr.length ? arr.reduce((s, v) => s + v, 0) / arr.length : 0;
}

function stddev(arr, avg) {
  if (arr.length < 2) return 0;
  const variance = arr.reduce((s, v) => s + (v - avg) ** 2, 0) / arr.length;
  return Math.sqrt(variance);
}

function bar(val, maxVal, w = 28) {
  if (!maxVal) return "░".repeat(w);
  const filled = Math.min(w, Math.floor(w * val / maxVal));
  return "█".repeat(filled) + "░".repeat(w - filled);
}

function statusColor(code) {
  if (!code)     return RED;
  if (code < 300) return GREEN;
  if (code < 400) return CYAN;
  if (code < 500) return YELLOW;
  return RED;
}

const STATUS_LABELS = {
  0:   "Connection Error / Timeout",
  200: "OK",
  301: "Moved Permanently",
  302: "Found (Redirect)",
  304: "Not Modified",
  400: "Bad Request",
  403: "Forbidden",
  404: "Not Found",
  419: "CSRF Token Mismatch",
  429: "Too Many Requests (Rate Limited)",
  500: "Internal Server Error",
  502: "Bad Gateway",
  503: "Service Unavailable",
};

// ──────────────────────────────────────────────────────────────────
// Report
// ──────────────────────────────────────────────────────────────────
function printReport() {
  const duration = (Date.now() / 1000) - startTs;
  const total    = results.length;

  console.log();
  console.log(c(BOLD + CYAN, "=".repeat(70)));
  console.log(c(BOLD + WHITE, "   LEP LOAD TEST REPORT  —  Bun Edition"));
  console.log(c(BOLD + CYAN, "=".repeat(70)));

  if (!total) {
    console.log(c(RED, "\n  No results — is the server reachable?\n"));
    return;
  }

  // ── Config
  console.log(`\n  ${c(BOLD, "Target:  ")} ${c(CYAN, BASE_URL)}`);
  console.log(`  ${c(BOLD, "Duration:")} ${duration.toFixed(1)}s  (planned: ${DURATION}s)`);
  console.log(`  ${c(BOLD, "VUs:     ")} ${VU_COUNT}`);
  console.log(`  ${c(BOLD, "Think:   ")} ~${THINK}s avg between requests`);

  // ── Summary
  const success    = results.filter(r => !r.error && r.status > 0 && r.status < 500);
  const failed     = results.filter(r => r.error  || r.status >= 500);
  const errRate    = total ? (failed.length / total * 100) : 0;
  const rps        = total / duration;
  const latencies  = success.map(r => r.latencyMs).sort((a, b) => a - b);

  console.log(`\n  ${c(BOLD + CYAN, "----  SUMMARY  ----")}`);
  console.log(`  ${c(DIM, "(PDF Download counts as 2 timed requests: Laravel redirect + MinIO transfer)")}`);
  console.log(`  Total Requests :  ${c(BOLD, String(total))}`);
  console.log(`  Successful     :  ${c(GREEN, String(success.length))}  (${(100 - errRate).toFixed(1)}%)`);
  console.log(`  Failed         :  ${c(failed.length ? RED : GREEN, String(failed.length))}  (${errRate.toFixed(1)}%)`);
  console.log(`  Throughput     :  ${c(GREEN, rps.toFixed(2) + " req/s")}`);
  console.log(`  Duration       :  ${duration.toFixed(1)}s`);

  // ── Latency
  if (latencies.length) {
    const p50   = pct(latencies, 50);
    const p75   = pct(latencies, 75);
    const p90   = pct(latencies, 90);
    const p95   = pct(latencies, 95);
    const p99   = pct(latencies, 99);
    const avg   = mean(latencies);
    const mn    = latencies[0];
    const mx    = latencies.at(-1);
    const sd    = stddev(latencies, avg);

    console.log(`\n  ${c(BOLD + CYAN, "----  LATENCY (ms)  ----")}`);
    console.log(`  ${"Metric".padEnd(10)} ${"Value".padStart(10)}  Distribution`);
    console.log(`  ${"-".repeat(10)} ${"-".repeat(10)}  ${"-".repeat(30)}`);

    const rows = [
      ["Min",    mn,  GREEN ],
      ["Mean",   avg, WHITE ],
      ["P50",    p50, GREEN ],
      ["P75",    p75, YELLOW],
      ["P90",    p90, YELLOW],
      ["P95",    p95, p95 > 2000 ? RED : YELLOW],
      ["P99",    p99, RED   ],
      ["Max",    mx,  RED   ],
      ["StdDev", sd,  DIM   ],
    ];

    for (const [label, val, col] of rows) {
      const b = bar(val, mx);
      console.log(`  ${label.padEnd(10)} ${c(col, `${val.toFixed(1)}ms`.padStart(10))}  ${c(DIM, b)}`);
    }

    // Grade
    let grade;
    if      (p95 < 500)  grade = c(GREEN  + BOLD, "  EXCELLENT  (P95 < 500ms)");
    else if (p95 < 1000) grade = c(GREEN,          "  GOOD       (P95 < 1000ms)");
    else if (p95 < 2000) grade = c(YELLOW,         "  FAIR       (P95 < 2s)    -- optimization needed");
    else if (p95 < 5000) grade = c(RED,             "  POOR       (P95 < 5s)    -- significant issues");
    else                  grade = c(RED + BOLD,     "  CRITICAL   (P95 > 5s)    -- unusable under load");

    console.log(`\n  ${c(BOLD, "Performance Grade:")}  ${grade}`);

    // ── Per-scenario
    console.log(`\n  ${c(BOLD + CYAN, "----  BY SCENARIO  ----")}`);
    console.log(
      `  ${"Scenario".padEnd(18)} ${"Reqs".padStart(6)} ${"OK".padStart(6)} ` +
      `${"Err".padStart(6)} ${"Mean".padStart(8)} ${"P95".padStart(8)} ${"Max".padStart(8)}`
    );
    console.log(`  ${"-".repeat(18)} ${"-".repeat(6)} ${"-".repeat(6)} ${"-".repeat(6)} ${"-".repeat(8)} ${"-".repeat(8)} ${"-".repeat(8)}`);

    // "PDF Download" is split at record-time into two separately-timed phases
    // (Laravel's redirect vs. the MinIO file transfer), so report those two
    // names in its place instead of the original combined scenario name.
    const REPORT_NAMES = [
      ...SCENARIOS.filter(s => s.name !== "PDF Download").map(s => s.name),
      "PDF: Laravel redirect",
      "PDF: MinIO transfer",
    ];

    for (const name of REPORT_NAMES) {
      const rs  = results.filter(r => r.name === name);
      if (!rs.length) continue;
      const ok  = rs.filter(r => !r.error && r.status < 500);
      const err = rs.filter(r => r.error  || r.status >= 500);
      const ls  = ok.map(r => r.latencyMs).sort((a, b) => a - b);
      const sM  = ls.length ? mean(ls).toFixed(0) + "ms"       : "N/A";
      const sP  = ls.length ? pct(ls, 95).toFixed(0) + "ms"    : "N/A";
      const sMx = ls.length ? ls.at(-1).toFixed(0) + "ms"      : "N/A";
      console.log(
        `  ${name.padEnd(18)} ${String(rs.length).padStart(6)} ` +
        `${c(GREEN, String(ok.length).padStart(6))} ` +
        `${c(err.length ? RED : GREEN, String(err.length).padStart(6))} ` +
        `${sM.padStart(8)} ${sP.padStart(8)} ${sMx.padStart(8)}`
      );
    }

    // ── Redirect target sanity check
    if (redirectHosts.size) {
      console.log(`\n  ${c(BOLD + CYAN, "----  PDF REDIRECT TARGETS  ----")}`);
      for (const [host, cnt] of [...redirectHosts.entries()].sort((a, b) => b[1] - a[1])) {
        const bad = isLoopbackOrPrivate(host);
        const tag = bad ? c(RED + BOLD, "  <-- LOOPBACK/PRIVATE, unreachable by real clients!") : "";
        console.log(`  ${c(bad ? RED : GREEN, host.padEnd(30))} x${String(cnt).padEnd(6)}${tag}`);
      }
    }

    // ── Status codes
    console.log(`\n  ${c(BOLD + CYAN, "----  STATUS CODES  ----")}`);
    const statusMap = new Map();
    for (const r of results) {
      statusMap.set(r.status, (statusMap.get(r.status) ?? 0) + 1);
    }
    for (const [code, cnt] of [...statusMap.entries()].sort((a, b) => a[0] - b[0])) {
      const pctV = (cnt / total * 100).toFixed(1);
      const hsh  = "#".repeat(Math.floor(cnt / total * 50));
      const lbl  = STATUS_LABELS[code] ?? "";
      console.log(
        `  ${c(statusColor(code), `HTTP ${String(code).padEnd(4)}`)}  ` +
        `${String(cnt).padStart(6)} (${pctV.padStart(5)}%)  ${c(DIM, hsh)}  ${c(DIM, lbl)}`
      );
    }

    // ── Error breakdown
    if (failed.length) {
      console.log(`\n  ${c(BOLD + RED, "----  ERROR BREAKDOWN  ----")}`);
      const errMap = new Map();
      for (const r of failed) {
        const key = r.error ?? `HTTP ${r.status}`;
        errMap.set(key, (errMap.get(key) ?? 0) + 1);
      }
      for (const [err, cnt] of [...errMap.entries()].sort((a, b) => b[1] - a[1])) {
        console.log(`  ${c(RED, "*")} ${err.padEnd(42)} x${cnt}`);
      }
    }

    // ── Throughput sparkline (5-second buckets)
    const BUCKET = 5;
    const buckets = new Map();
    if (results.length) {
      const t0 = results[0].ts;
      for (const r of results) {
        const b = Math.floor((r.ts - t0) / BUCKET);
        buckets.set(b, (buckets.get(b) ?? 0) + 1);
      }
    }
    if (buckets.size > 3) {
      console.log(`\n  ${c(BOLD + CYAN, `----  THROUGHPUT OVER TIME (req per ${BUCKET}s)  ----`)}`);
      const maxB   = Math.max(...buckets.values()) || 1;
      const keys   = [...buckets.keys()].sort((a, b) => a - b).slice(0, 55);
      const vals   = keys.map(k => buckets.get(k) ?? 0);
      const H = 5;
      for (let row = H; row >= 1; row--) {
        const threshold = maxB * row / H;
        const line = vals.map(v => v >= threshold ? c(GREEN, "|") : " ").join("");
        const yLbl = (row === H || row === 1)
          ? `${(maxB * row / H / BUCKET).toFixed(1)}rps`.padStart(7)
          : " ".repeat(7);
        console.log(`  ${c(DIM, yLbl)} |${line}`);
      }
      console.log(`  ${c(DIM, " ".repeat(9) + "+" + "-".repeat(keys.length))}`);
      console.log(`  ${c(DIM, " ".repeat(10) + "0s" + " ".repeat(Math.max(0, keys.length - 10)) + `${duration.toFixed(0)}s`)}`);
    }

    // ── Recommendations
    console.log(`\n  ${c(BOLD + CYAN, "----  RECOMMENDATIONS  ----")}`);
    const recs = [];

    if (p95  > 1000) recs.push(["HIGH", "P95 > 1s  -- enable OPcache; switch SESSION_DRIVER + CACHE_STORE to file or redis in .env"]);
    if (p99  > 3000) recs.push(["HIGH", "P99 > 3s  -- DB slow under load; add indexes + tune MariaDB innodb_buffer_pool_size"]);
    if (errRate > 5) recs.push(["HIGH", `Error rate ${errRate.toFixed(1)}%  -- check PHP-FPM pm.max_children; may be running out of workers`]);
    if (statusMap.get(429)) recs.push(["WARN", `HTTP 429 x${statusMap.get(429)}  -- throttle middleware firing; install Redis + raise limits`]);
    if (statusMap.get(500)) recs.push(["HIGH", `HTTP 500 x${statusMap.get(500)}  -- check /var/www/lep/laravel-app/storage/logs/laravel.log`]);
    if (rps < 5 && VU_COUNT >= 20) recs.push(["HIGH", `Only ${rps.toFixed(1)} RPS with ${VU_COUNT} VUs -- server bottlenecked; check CPU / RAM / php-fpm`]);
    if (p50 < 500 && p99 > 3000)   recs.push(["WARN", "High P50→P99 spread -- intermittent DB/GC spikes; Redis sessions will flatten this"]);

    for (const [host, cnt] of redirectHosts.entries()) {
      if (isLoopbackOrPrivate(host)) {
        recs.push(["HIGH", `${cnt}x PDF redirects point at loopback/private host "${host}" -- MINIO_ENDPOINT/'url' in config/filesystems.php is unreachable from real clients; downloads are broken in production, not just slow`]);
      }
    }
    const laravelPhase = results.filter(r => r.name === "PDF: Laravel redirect" && !r.error && r.status < 500);
    const minioPhase    = results.filter(r => r.name === "PDF: MinIO transfer"    && !r.error && r.status < 500);
    if (laravelPhase.length && minioPhase.length) {
      const lMean = mean(laravelPhase.map(r => r.latencyMs));
      const mMean = mean(minioPhase.map(r => r.latencyMs));
      if (mMean > lMean * 3 && mMean > 1000) {
        recs.push(["HIGH", `MinIO transfer (mean ${mMean.toFixed(0)}ms) is far slower than Laravel's own redirect (mean ${lMean.toFixed(0)}ms) -- MinIO itself is the bottleneck (shared-VPS CPU/disk/network contention), not PHP-FPM/Laravel`]);
      } else if (lMean > mMean * 3 && lMean > 1000) {
        recs.push(["HIGH", `Laravel's redirect (mean ${lMean.toFixed(0)}ms) is far slower than the actual MinIO transfer (mean ${mMean.toFixed(0)}ms) -- the bottleneck is PHP-FPM/DB, not MinIO; check pm.max_children and the Project lookup query`]);
      }
    }
    const minioErr = results.filter(r => r.name === "PDF: MinIO transfer" && (r.error || r.status >= 500));
    if (minioErr.length) {
      recs.push(["WARN", `${minioErr.length}x MinIO transfer failures/timeouts -- check MinIO's own resource usage (CPU/RAM/disk I/O) on the shared VPS under concurrent load`]);
    }

    if (!recs.length) recs.push(["OK", "No critical issues at this load level. Try --vu 100 to stress-test further."]);

    for (const [lvl, msg] of recs) {
      const col = lvl === "HIGH" ? RED : lvl === "WARN" ? YELLOW : GREEN;
      console.log(`  ${c(col, `[${lvl}]`.padEnd(7))} ${msg}`);
    }
  }

  console.log();
  console.log(c(BOLD + CYAN, "=".repeat(70)));
  console.log();
}

// ──────────────────────────────────────────────────────────────────
// Main
// ──────────────────────────────────────────────────────────────────
console.log();
console.log(c(BOLD + CYAN, "  " + "=".repeat(64)));
console.log(c(BOLD + WHITE, "         LEP LOAD TEST  --  Bun Edition"));
console.log(c(BOLD + CYAN, "  " + "=".repeat(64)));
console.log();
console.log(`  Target   : ${c(CYAN, BASE_URL)}`);
console.log(`  VUs      : ${c(BOLD, String(VU_COUNT))}`);
console.log(`  Duration : ${c(BOLD, String(DURATION))}s`);
console.log(`  Think    : ~${THINK}s avg between requests per VU`);
console.log(`  Ramp-up  : ${RAMP_SEC}s  (VUs start gradually)`);
console.log();
console.log(c(DIM, "  Press Ctrl+C to stop early and still see the report."));

startTs = Date.now() / 1000;

// Stagger VU start across ramp window
const rampDelay = (RAMP_SEC * 1000) / VU_COUNT;
const vuPromises = [];
for (let i = 0; i < VU_COUNT; i++) {
  await sleep(rampDelay);
  vuPromises.push(virtualUser(i));
}

// Live progress every 2s
const progressInterval = setInterval(printProgress, 2000);

// Wait for test duration (minus ramp already elapsed)
const elapsed = (Date.now() / 1000) - startTs;
const remaining = Math.max(0, DURATION - elapsed) * 1000;
await sleep(remaining);

// Stop everything
stopped = true;
clearInterval(progressInterval);
process.stdout.write("\n");

// Let in-flight requests drain (max 3s)
await sleep(3000);

printReport();
process.exit(0);
