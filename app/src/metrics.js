import http from 'node:http';
import client from 'prom-client';
import * as cache from './cache.js';
import { config } from './config.js';
import * as db from './db.js';
import { log } from './logger.js';
import * as storage from './storage.js';

// Prometheus metrics of this replica, served on their own port (see config.js).
// The load balancer already measures traffic at the edge, but it only keeps
// averages; a histogram here gives real percentiles, and the dependency
// checks show what the application itself can reach.

const registry = new client.Registry();

// Standard Node.js process metrics: CPU, memory, heap, event loop lag, GC.
client.collectDefaultMetrics({ register: registry });

// Request duration as a histogram, the way Prometheus can compute any
// percentile (p95, p99) across replicas. route is the Express route pattern,
// never the raw URL, so the number of series stays small.
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of the HTTP requests served by the application.',
  labelNames: ['method', 'route', 'status_code'],
  registers: [registry],
});

// Load balancer health checks, not user traffic: they would dominate the rate.
const UNMEASURED_PATHS = new Set(['/live']);

export function observeRequest(req, res, seconds) {
  if (UNMEASURED_PATHS.has(req.path)) return;
  // Files from public/ and unknown paths have no Express route.
  let route = 'static';
  if (req.route) route = req.baseUrl + req.route.path;
  else if (res.statusCode === 404) route = 'not_found';
  httpRequestDuration.observe({ method: req.method, route, status_code: res.statusCode }, seconds);
}

// 1 when this replica can use the dependency, 0 when it cannot. Checked on
// every scrape (every 15 s), so the value is always current. Disabled
// dependencies (no cache in dev) are left out instead of reported as down.
new client.Gauge({
  name: 'bugtracker_dependency_up',
  help: 'Whether this replica can reach the dependency (1) or not (0).',
  labelNames: ['dependency'],
  registers: [registry],
  async collect() {
    const checks = { database: db.ping };
    if (cache.enabled) checks.cache = cache.ping;
    if (storage.enabled) checks.storage = storage.ping;
    const names = Object.keys(checks);
    const results = await Promise.all(names.map((name) => checks[name]()));
    names.forEach((name, i) => this.set({ dependency: name }, results[i] ? 1 : 0));
  },
});

const server = http.createServer(async (req, res) => {
  if (req.url !== '/metrics') {
    res.writeHead(404).end();
    return;
  }
  try {
    const body = await registry.metrics();
    res.writeHead(200, { 'Content-Type': registry.contentType }).end(body);
  } catch (error) {
    log.error('metrics_failed', { reason: error.message });
    res.writeHead(500).end();
  }
});

// Same handling as the application port: a port that cannot be opened is
// reported as one log line and the process exits.
server.on('error', (error) => {
  log.error('metrics_listen_failed', { port: config.metricsPort, reason: error.message });
  process.exit(1);
});

export function start() {
  server.listen(config.metricsPort);
}

export function close() {
  return new Promise((resolve) => server.close(resolve));
}
