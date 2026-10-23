// Links the landing page shows.

/** Frontier's usage guide: setup, configuration, FAQ. */
export const FRONTIER_USAGE_URL = 'http://go/frontier-usage';

/** Every frontier-app-base config option and its default. */
export const FRONTIER_CONFIG_REFERENCE_URL =
  'https://github.com/persona-id/jsonnet-libs/blob/main/frontier-app-base/config.libsonnet';

export const PERSONA_LOGO_URL = 'https://assets.withpersona.com/brand/logos/persona-logo-color-on-light.svg';

export function repoUrl(org: string, appName: string): string {
  return `https://github.com/${org}/${appName}`;
}

export function readmeUrl(org: string, appName: string): string {
  return `${repoUrl(org, appName)}#readme`;
}

/**
 * The service's page in Datadog APM, filtered to one environment. Same form as
 * the APM links in persona-infrastructure-datadog's monitors.
 */
export function datadogApmUrl(service: string, env: string): string {
  return `https://app.datadoghq.com/apm/entity/${encodeURIComponent(`service:${service}`)}?env=${encodeURIComponent(env)}`;
}
