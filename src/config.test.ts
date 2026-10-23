import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { DEFAULT_APP_NAME, appNameFromLibsonnet, loadConfig } from './config.js';
import { datadogApmUrl, readmeUrl } from './links.js';

describe('loadConfig', () => {
  it('defaults for a local run with no app.libsonnet', () => {
    expect(loadConfig({}, () => undefined)).toEqual({
      port: 8080,
      appName: DEFAULT_APP_NAME,
      visibility: 'private',
      environment: 'local',
      ddService: DEFAULT_APP_NAME,
      githubOrg: 'persona-id',
    });
  });

  it('reads the values kubernetes/jsonnet sets', () => {
    expect(
      loadConfig({
        PORT: '9090',
        FRONTIER_APP_NAME: 'my-app',
        FRONTIER_VISIBILITY: 'public',
        DD_ENV: 'production',
        DD_SERVICE: 'my-app-svc',
      })
    ).toMatchObject({
      port: 9090,
      appName: 'my-app',
      visibility: 'public',
      environment: 'production',
      ddService: 'my-app-svc',
    });
  });

  it("uses app.libsonnet's name for a local run of a generated repo", () => {
    const libsonnet = [
      "// A comment mentioning name: 'other'",
      '{',
      "  name: 'my-new-app',",
      '',
      "  repoURL: 'https://github.com/persona-id/' + self.name,",
      '}',
      '',
    ].join('\n');
    expect(loadConfig({}, () => libsonnet)).toMatchObject({
      appName: 'my-new-app',
      ddService: 'my-new-app',
      environment: 'local',
    });
  });

  it('prefers FRONTIER_APP_NAME over app.libsonnet', () => {
    const read = () => "{\n  name: 'my-new-app',\n}\n";
    expect(loadConfig({ FRONTIER_APP_NAME: 'my-app' }, read).appName).toBe('my-app');
  });

  it('falls back to the default when app.libsonnet has no plain name field', () => {
    expect(loadConfig({}, () => '{}\n').appName).toBe(DEFAULT_APP_NAME);
    expect(loadConfig({}, () => "{\n  name: 'a' + 'b',\n}\n").appName).toBe(DEFAULT_APP_NAME);
  });

  it("reads this repository's own app.libsonnet by default", () => {
    const libsonnet = readFileSync('kubernetes/jsonnet/common/app.libsonnet', 'utf8');
    expect(loadConfig({}).appName).toBe(appNameFromLibsonnet(libsonnet));
  });

  it('falls back to the app name for DD_SERVICE and to 8080 for a bad PORT', () => {
    expect(loadConfig({ FRONTIER_APP_NAME: 'my-app', PORT: 'nope' })).toMatchObject({
      port: 8080,
      ddService: 'my-app',
    });
  });
});

describe('links', () => {
  it('links the service in Datadog APM for one environment', () => {
    expect(datadogApmUrl('my-app', 'production')).toBe(
      'https://app.datadoghq.com/apm/entity/service%3Amy-app?env=production'
    );
  });

  it("links the repository's README", () => {
    expect(readmeUrl('persona-id', 'my-app')).toBe('https://github.com/persona-id/my-app#readme');
  });
});
