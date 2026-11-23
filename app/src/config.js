import os from 'node:os';

// Reads and validates every environment variable in one place, once, at startup.
// If something is missing or malformed the process fails immediately with a
// clear message, instead of crashing later in the middle of a request.

// Returns the variable's value, or undefined when it is unset or empty.
const raw = (name) => {
  const value = process.env[name];
  return value === undefined || value === '' ? undefined : value;
};

const text = (name) => {
  const value = raw(name);
  if (value === undefined) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
};

const integer = (name, fallback) => {
  const value = raw(name);
  if (value === undefined) return fallback;
  const number = Number(value);
  if (!Number.isInteger(number) || number < 1) {
    throw new Error(`${name} must be a positive integer, got "${value}"`);
  }
  return number;
};

const oneOf = (name, allowed, fallback) => {
  const value = raw(name) ?? fallback;
  if (!allowed.includes(value)) {
    throw new Error(`${name} must be one of ${allowed.join(', ')}, got "${value}"`);
  }
  return value;
};

const cacheEnabled = oneOf('CACHE_ENABLED', ['true', 'false'], 'false') === 'true';

// Optional absolute http(s) URL; a typo fails at startup instead of on every check.
const url = (name) => {
  const value = raw(name);
  if (value === undefined) return undefined;
  if (!URL.canParse(value) || !/^https?:$/.test(new URL(value).protocol)) {
    throw new Error(`${name} must be an http(s) URL, got "${value}"`);
  }
  return value;
};

const storageHealthUrl = url('STORAGE_HEALTH_URL');

// Optional browser links to the monitoring tools of this environment, shown
// in the System view. Only links: the app never calls them.
const monitoring = Object.fromEntries(
  Object.entries({
    grafana: url('GRAFANA_URL'),
    prometheus: url('PROMETHEUS_URL'),
    alertmanager: url('ALERTMANAGER_URL'),
    mail: url('MAIL_URL'),
  }).filter(([, value]) => value),
);

export const config = {
  // Name of this replica. Docker sets the hostname of each container, so it
  // matches the container name shown by `docker ps`.
  instance: os.hostname(),
  env: oneOf('NODE_ENV', ['development', 'production'], 'development'),
  port: integer('PORT', 3000),
  // Separate port for Prometheus, so /metrics is never reachable through the
  // load balancer, which only forwards to the application port. 9464 is the
  // default of OpenTelemetry's Prometheus exporter.
  metricsPort: integer('METRICS_PORT', 9464),
  logLevel: oneOf('LOG_LEVEL', ['debug', 'info', 'warn', 'error'], 'info'),
  db: {
    host: text('DB_HOST'),
    port: integer('DB_PORT', 5432),
    database: text('POSTGRES_DB'),
    user: text('POSTGRES_USER'),
    password: text('POSTGRES_PASSWORD'),
  },
  // Redis settings are only read (and required) when the cache is enabled.
  cache: cacheEnabled
    ? {
        enabled: true,
        host: text('REDIS_HOST'),
        port: integer('REDIS_PORT', 6379),
        password: text('REDIS_PASSWORD'),
        ttlSeconds: integer('CACHE_TTL_SECONDS', 60),
      }
    : { enabled: false },
  // Object storage is only checked when its health URL is given.
  storage: storageHealthUrl ? { enabled: true, healthUrl: storageHealthUrl } : { enabled: false },
  monitoring,
};

// Same shape as config but without any secret: this is the only version
// that is allowed to be printed in logs.
export const describeConfig = () => ({
  instance: config.instance,
  env: config.env,
  port: config.port,
  metricsPort: config.metricsPort,
  logLevel: config.logLevel,
  db: {
    host: config.db.host,
    port: config.db.port,
    database: config.db.database,
    user: config.db.user,
  },
  cache: config.cache.enabled
    ? {
        enabled: true,
        host: config.cache.host,
        port: config.cache.port,
        ttlSeconds: config.cache.ttlSeconds,
      }
    : { enabled: false },
  storage: config.storage,
  monitoring: config.monitoring,
});
