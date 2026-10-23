// Entrypoint. Datadog APM is not set up here: the Dockerfile and `npm start`
// load dd-trace with `node --import dd-trace/initialize.mjs`, which is how it
// hooks ESM and auto-instruments express and outbound HTTP. It reads DD_SERVICE,
// DD_ENV and DD_AGENT_HOST from the environment, set in kubernetes/jsonnet. With
// no agent reachable (locally, in tests) it drops traces quietly.
import { createApp } from './app.js';
import { loadConfig } from './config.js';

const config = loadConfig();
const server = createApp(config).listen(config.port, () => {
  console.log(`${config.appName} (${config.environment}) listening on :${config.port}`);
});

// Knative sends SIGTERM before stopping a revision: finish in-flight requests.
function shutdown(signal: string) {
  console.log(`${signal} received, shutting down`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 10_000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
