import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { afterEach, describe, expect, it } from 'vitest';
import { createApp } from './app.js';
import { type AppConfig, loadConfig } from './config.js';
import { oracleChatUrl } from './oracle.js';

let server: Server | undefined;

afterEach(async () => {
  await new Promise<void>((resolve) => (server ? server.close(() => resolve()) : resolve()));
  server = undefined;
});

async function start(overrides: Partial<AppConfig> = {}): Promise<string> {
  const config = { ...loadConfig({ FRONTIER_APP_NAME: 'my-app', DD_ENV: 'development' }), ...overrides };
  server = createApp(config).listen(0);
  await new Promise<void>((resolve) => server!.once('listening', () => resolve()));
  return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}

describe('GET /healthz', () => {
  it('answers 200', async () => {
    const res = await fetch(`${await start()}/healthz`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe('ok');
  });
});

describe('GET /', () => {
  it('shows the app, its environment and its links', async () => {
    const res = await fetch(`${await start()}/`);
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toMatch(/text\/html/);
    const html = await res.text();
    expect(html).toContain('<h1>my-app</h1>');
    expect(html).toContain('<dt>Environment</dt><dd>development</dd>');
    expect(html).toContain('https://app.datadoghq.com/apm/entity/service%3Amy-app?env=development');
    expect(html).toContain('http://go/frontier-usage');
    expect(html).toContain('https://github.com/persona-id/my-app#readme');
    expect(html).toContain('https://github.com/persona-id/jsonnet-libs/blob/main/frontier-app-base/config.libsonnet');
    expect(html).toContain('https://assets.withpersona.com/brand/logos/persona-logo-color-on-light.svg');
  });

  it.each(['private', 'none'])('shows Build in Oracle when visibility is %s', async (visibility) => {
    const html = await (await fetch(`${await start({ visibility })}/`)).text();
    expect(html).toContain('Build in Oracle');
    expect(html).toContain('action="/build-in-oracle"');
    expect(html).toContain('maxlength="2000"');
    expect(html).toContain('Dispatch an Oracle Editor session on persona-id/my-app (https://github.com/persona-id/my-app)');
  });

  it('hides Build in Oracle when the app is public', async () => {
    const html = await (await fetch(`${await start({ visibility: 'public' })}/`)).text();
    expect(html).not.toContain('Build in Oracle');
    expect(html).not.toContain('/build-in-oracle');
  });

  it('escapes values it renders', async () => {
    const html = await (await fetch(`${await start({ environment: '<script>' })}/`)).text();
    expect(html).not.toContain('<script>');
    expect(html).toContain('&lt;script&gt;');
  });
});

describe('GET /build-in-oracle', () => {
  it("redirects to a new Oracle chat for this app's repo with the change filled in", async () => {
    const change = 'Add a dark mode toggle.\nSave it.';
    const res = await fetch(`${await start()}/build-in-oracle?change=${encodeURIComponent(change)}`, {
      redirect: 'manual',
    });
    expect(res.status).toBe(302);
    expect(res.headers.get('location')).toBe(oracleChatUrl('https://github.com/persona-id/my-app', change));
    const prompt = new URL(res.headers.get('location')!).searchParams.get('prompt')!;
    expect(prompt).toContain('\n\nChange:\nAdd a dark mode toggle.\nSave it.\n\nThen monitor');
  });

  it('redirects when an emoji straddles the length cap', async () => {
    const change = `${'a'.repeat(1999)}\u{1F600}`;
    const res = await fetch(`${await start()}/build-in-oracle?change=${encodeURIComponent(change)}`, {
      redirect: 'manual',
    });
    expect(res.status).toBe(302);
    const location = new URL(res.headers.get('location')!);
    expect(location.origin).toBe('https://oracle.withpersona.ai');
    expect(location.searchParams.get('prompt')).toContain(`\n\nChange:\n${'a'.repeat(1999)}\n\nThen monitor`);
  });

  it('is not found when the app is public', async () => {
    const res = await fetch(`${await start({ visibility: 'public' })}/build-in-oracle?change=x`, {
      redirect: 'manual',
    });
    expect(res.status).toBe(404);
  });
});
