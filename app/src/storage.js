import { config } from './config.js';
import { log } from './logger.js';

// Object storage that serves the images (MinIO in this project). The
// web never reads from it, the load balancer does; the web only reports
// whether it is alive, by calling its HTTP health endpoint.

const settings = config.storage;
export const enabled = settings.enabled;

// null = unknown yet, true = reachable, false = unreachable.
let storageAvailable = null;

// Logs only when the state changes, same idea as in db.js.
function recordAvailability(available, reason) {
  if (storageAvailable === available) return;
  storageAvailable = available;

  if (available) {
    log.info('storage_available');
  } else {
    log.error('storage_unavailable', { reason });
  }
}

// Returns true when the health endpoint answers 2xx within 2 seconds.
export async function ping() {
  if (!enabled) return false;
  try {
    const response = await fetch(settings.healthUrl, { signal: AbortSignal.timeout(2000) });
    recordAvailability(response.ok, `HTTP ${response.status}`);
    return response.ok;
  } catch (error) {
    // fetch hides the network error (e.g. ECONNREFUSED) in error.cause.
    recordAvailability(false, error.cause?.code || error.message);
    return false;
  }
}
