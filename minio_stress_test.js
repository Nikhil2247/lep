#!/usr/bin/env bun
/**
 * MinIO Direct Concurrency Stress Test
 * =====================================
 * Isolates MinIO's own concurrent-serving capacity from Laravel/PHP-FPM.
 * Fetches a real signed download URL via Laravel once per project (the
 * only step that touches Laravel), then hammers those exact MinIO URLs
 * directly at increasing concurrency "waves" to find the point where
 * MinIO itself starts failing or degrading.
 *
 * Usage:
 *   bun minio_stress_test.js
 *   bun minio_stress_test.js --url https://nagaland.lep.2026.vibha.org --projects 1,2,3 --steps 5,10,20,40,80
 */

const R = "\x1b[0m", BOLD = "\x1b[1m", DIM = "\x1b[2m";
const RED = "\x1b[91m", GREEN = "\x1b[92m", YELLOW = "\x1b[93m", CYAN = "\x1b[96m";
const c = (col, txt) => `${col}${txt}${R}`;

const argv = process.argv.slice(2);
const arg = (flag, def) => { const i = argv.indexOf(flag); return i !== -1 ? argv[i + 1] : def; };

const BASE_URL    = arg("--url", "https://nagaland.lep.2026.vibha.org");
const PROJECTS    = arg("--projects", "1,2,3").split(",").map(s => s.trim());
const STEPS       = arg("--steps", "5,10,20,40,80").split(",").map(n => parseInt(n, 10));
const TIMEOUT_MS  = parseInt(arg("--timeout", "30000"), 10);
const COOLDOWN_MS = parseInt(arg("--cooldown", "2000"), 10);

async function getSignedUrl(projectId) {
  const res = await fetch(`${BASE_URL}/projects/${projectId}/download`, {
    method: "GET",
    redirect: "manual",
    signal: AbortSignal.timeout(15_000),
  });
  if (res.status < 300 || res.status >= 400) {
    throw new Error(`expected a redirect, got HTTP ${res.status}`);
  }
  const loc = res.headers.get("location");
  if (!loc) throw new Error("no Location header on the redirect");
  return new URL(loc, BASE_URL).href;
}

async function fetchOnce(url) {
  const t0 = performance.now();
  try {
    const res = await fetch(url, { method: "GET", signal: AbortSignal.timeout(TIMEOUT_MS) });
    await res.arrayBuffer();
    return { ok: res.status < 400, status: res.status, ms: performance.now() - t0 };
  } catch (e) {
    return {
      ok: false, status: 0, ms: performance.now() - t0,
      error: e.name === "TimeoutError" ? "TIMEOUT" : e.name,
    };
  }
}

function stats(results) {
  const ok  = results.filter(r => r.ok);
  const lat = ok.map(r => r.ms).sort((a, b) => a - b);
  const mean = lat.length ? lat.reduce((s, v) => s + v, 0) / lat.length : 0;
  const p95  = lat.length ? lat[Math.floor(lat.length * 0.95)] : 0;
  const max  = lat.length ? lat.at(-1) : 0;
  return {
    total: results.length,
    ok: ok.length,
    errRate: results.length ? 100 * (results.length - ok.length) / results.length : 0,
    mean, p95, max,
  };
}

console.log(c(BOLD + CYAN, "\n=== MinIO Direct Concurrency Stress Test ===\n"));
console.log(c(DIM, "This bypasses Laravel/PHP-FPM entirely after the initial URL fetch —"));
console.log(c(DIM, "everything below hits MinIO directly, so any collapse is MinIO's own.\n"));
console.log(`Fetching ${PROJECTS.length} signed URL(s) from Laravel first...`);

const urls = [];
for (const p of PROJECTS) {
  try {
    const u = await getSignedUrl(p);
    urls.push(u);
    console.log(`  project ${p} -> ${c(GREEN, new URL(u).hostname)}  ${c(DIM, u.slice(0, 90) + "...")}`);
  } catch (e) {
    console.log(`  ${c(RED, "SKIP")} project ${p}: ${e.message}`);
  }
}

if (!urls.length) {
  console.log(c(RED, "\nNo signed URLs obtained — check the target/project ids and try again.\n"));
  process.exit(1);
}

console.log(`\n  ${c(BOLD, "Concurrency")}  ${"OK".padStart(5)} ${"Err%".padStart(6)} ${"Mean".padStart(9)} ${"P95".padStart(9)} ${"Max".padStart(9)}`);
console.log(`  ${"-".repeat(11)}  ${"-".repeat(5)} ${"-".repeat(6)} ${"-".repeat(9)} ${"-".repeat(9)} ${"-".repeat(9)}`);

const rows = [];
for (const n of STEPS) {
  const wave = Array.from({ length: n }, (_, i) => urls[i % urls.length]);
  const t0 = performance.now();
  const results = await Promise.all(wave.map(u => fetchOnce(u)));
  const waveMs = performance.now() - t0;
  const s = stats(results);
  rows.push({ n, ...s });

  const col = s.errRate > 20 ? RED : s.errRate > 0 ? YELLOW : GREEN;
  console.log(
    `  ${String(n).padStart(11)}  ${c(col, String(s.ok).padStart(5))} ` +
    `${c(col, (s.errRate.toFixed(0) + "%").padStart(6))} ` +
    `${(s.mean.toFixed(0) + "ms").padStart(9)} ${(s.p95.toFixed(0) + "ms").padStart(9)} ${(s.max.toFixed(0) + "ms").padStart(9)}  ` +
    `${c(DIM, `wave took ${(waveMs / 1000).toFixed(1)}s`)}`
  );

  await new Promise(r => setTimeout(r, COOLDOWN_MS));
}

// Find the first step where things clearly got worse than the first step
const baseline = rows[0];
const collapse = rows.find(r => r.errRate > 10 || r.mean > baseline.mean * 5);

console.log();
if (collapse) {
  console.log(c(BOLD + RED, `Collapse point: concurrency ~${collapse.n} — error rate jumped to ${collapse.errRate.toFixed(0)}% / mean latency ${collapse.mean.toFixed(0)}ms.`));
  console.log(c(DIM, "A SHARP jump at one specific step (not gradual) usually means a hard limit:"));
  console.log(c(DIM, "  - MinIO process file-descriptor limit (check: cat /proc/$(pgrep minio)/limits | grep 'open files')"));
  console.log(c(DIM, "  - A reverse proxy in front of files.placeintern.com hitting its own worker/connection cap"));
  console.log(c(DIM, "A GRADUAL climb across steps instead usually means real resource contention:"));
  console.log(c(DIM, "  - CPU/disk I/O/network bandwidth shared with PHP-FPM/MariaDB/Node/Postgres on the same VPS"));
} else {
  console.log(c(GREEN, "No clear collapse point up to the highest concurrency tested — try higher --steps."));
}
console.log();
