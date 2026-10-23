// Runtime settings, all from the environment. In the cluster they are set by
// kubernetes/jsonnet (common/config.libsonnet and <env>/config.libsonnet); the
// defaults are for running locally with `npm run dev`.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export interface AppConfig {
  /** Port to listen on. Knative sets PORT; 8080 is its default. */
  port: number;
  /** The app's name, which is also its GitHub repository's name. */
  appName: string;
  /** private, public or none, as in common/config.libsonnet. */
  visibility: string;
  /** Environment: production, development, or local outside the cluster. */
  environment: string;
  /** Datadog service name, the one traces are reported under. */
  ddService: string;
  /** GitHub org the repository lives in. */
  githubOrg: string;
}

export const DEFAULT_APP_NAME = 'persona-template-frontier-app';

function nonEmpty(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

/**
 * kubernetes/jsonnet/common/app.libsonnet, resolved from the repository root
 * (one level up from src/ under `npm run dev`, or dist/ under `npm start`).
 */
export const APP_LIBSONNET_URL = new URL('../kubernetes/jsonnet/common/app.libsonnet', import.meta.url);

/** The file's contents, or undefined when it is missing (as in the image). */
function readAppLibsonnet(): string | undefined {
  try {
    return readFileSync(fileURLToPath(APP_LIBSONNET_URL), 'utf8');
  } catch {
    return undefined;
  }
}

/**
 * The app's name from app.libsonnet's top-level `name: '<name>',` field, the
 * line Frontier rewrites (persona-frontier-ui applyAppName) when it generates
 * the repo. Undefined when the field is missing or not a plain string.
 */
export function appNameFromLibsonnet(source: string | undefined): string | undefined {
  return nonEmpty(/^  name: '([^'\\\n]*)',?[ \t]*$/m.exec(source ?? '')?.[1]);
}

/**
 * Settings from `env`. The app name is FRONTIER_APP_NAME when set (always, in
 * the cluster); otherwise, as for `npm run dev` in a generated repo, the name
 * in kubernetes/jsonnet/common/app.libsonnet, and only then DEFAULT_APP_NAME.
 * `readLibsonnet` is injectable for tests.
 */
export function loadConfig(
  env: NodeJS.ProcessEnv = process.env,
  readLibsonnet: () => string | undefined = readAppLibsonnet
): AppConfig {
  const appName =
    nonEmpty(env.FRONTIER_APP_NAME) ?? appNameFromLibsonnet(readLibsonnet()) ?? DEFAULT_APP_NAME;
  const port = Number.parseInt(nonEmpty(env.PORT) ?? '', 10);
  return {
    port: Number.isInteger(port) && port > 0 && port < 65536 ? port : 8080,
    appName,
    visibility: nonEmpty(env.FRONTIER_VISIBILITY) ?? 'private',
    environment: nonEmpty(env.DD_ENV) ?? 'local',
    ddService: nonEmpty(env.DD_SERVICE) ?? appName,
    githubOrg: 'persona-id',
  };
}
