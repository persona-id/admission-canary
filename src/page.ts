// The landing page: server-rendered HTML with inline CSS. No client build and
// no client JavaScript; the Build in Oracle form is a plain GET that
// /build-in-oracle redirects to Oracle.
import type { AppConfig } from './config.js';
import {
  FRONTIER_CONFIG_REFERENCE_URL,
  FRONTIER_USAGE_URL,
  PERSONA_LOGO_URL,
  datadogApmUrl,
  readmeUrl,
  repoUrl,
} from './links.js';
import { ORACLE_CHANGE_MAX_LENGTH, isInternal, oracleBuildPrompt } from './oracle.js';

export const BUILD_IN_ORACLE_PATH = '/build-in-oracle';

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Tabler's "sparkles" icon, the one on the Frontier UI's button.
const SPARKLES_ICON =
  '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M16 18a2 2 0 0 1 2 2a2 2 0 0 1 2 -2a2 2 0 0 1 -2 -2a2 2 0 0 1 -2 2zm0 -12a2 2 0 0 1 2 2a2 2 0 0 1 2 -2a2 2 0 0 1 -2 -2a2 2 0 0 1 -2 2zm-7 12a6 6 0 0 1 6 -6a6 6 0 0 1 -6 -6a6 6 0 0 1 -6 6a6 6 0 0 1 6 6z" /></svg>';

const STYLES = `
  :root { color-scheme: light; --ink: #1a1b25; --muted: #5f6370; --line: #e4e5ea; --bg: #f7f7fa; }
  * { box-sizing: border-box; }
  body { margin: 0; font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; color: var(--ink); background: var(--bg); }
  header { display: flex; align-items: center; gap: 12px; padding: 16px 32px; background: #fff; border-bottom: 1px solid var(--line); }
  header img { height: 24px; }
  header .product { color: var(--muted); font-weight: 500; }
  main { max-width: 760px; margin: 40px auto; padding: 0 24px; }
  h1 { font-size: 28px; margin: 0 0 4px; }
  .lede { color: var(--muted); margin: 0 0 24px; }
  .card { background: #fff; border: 1px solid var(--line); border-radius: 8px; padding: 20px 24px; margin-bottom: 20px; }
  .card h2 { font-size: 16px; margin: 0 0 12px; }
  dl { display: grid; grid-template-columns: max-content 1fr; gap: 6px 20px; margin: 0; }
  dt { color: var(--muted); }
  dd { margin: 0; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  ul { margin: 0; padding-left: 20px; }
  li { margin: 4px 0; }
  a { color: #4c6ef5; }
  .oracle-button { display: inline-flex; align-items: center; gap: 8px; padding: 0 18px; height: 36px; border: 0; border-radius: 4px; color: #fff; font-weight: 600; font-size: 14px; cursor: pointer; background: linear-gradient(45deg, #7950f2 0%, #4c6ef5 100%); list-style: none; }
  .oracle-button::-webkit-details-marker { display: none; }
  .oracle-button:hover { filter: brightness(1.05); }
  details[open] .oracle-button { margin-bottom: 16px; }
  label { display: block; font-weight: 500; margin-bottom: 4px; }
  textarea { width: 100%; min-height: 110px; padding: 8px 10px; border: 1px solid var(--line); border-radius: 4px; font: inherit; resize: vertical; }
  .hint { color: var(--muted); font-size: 13px; }
  pre { background: var(--bg); border: 1px solid var(--line); border-radius: 4px; padding: 10px 12px; white-space: pre-wrap; overflow-wrap: anywhere; font-size: 12px; }
  .actions { display: flex; justify-content: flex-end; margin-top: 12px; }
  .submit { padding: 0 16px; height: 34px; border: 0; border-radius: 4px; background: #4c6ef5; color: #fff; font-weight: 600; cursor: pointer; }
`;

function buildInOracle(config: AppConfig): string {
  if (!isInternal(config.visibility)) return '';
  const slug = `${config.githubOrg}/${config.appName}`;
  return `
    <section class="card" id="build-in-oracle">
      <details>
        <summary class="oracle-button">${SPARKLES_ICON}Build in Oracle</summary>
        <p class="hint">Describe the change you want. Open in Oracle starts a new Oracle chat in a new tab with this prompt filled in, ready for you to send.</p>
        <form action="${BUILD_IN_ORACLE_PATH}" method="get" target="_blank" rel="noopener noreferrer">
          <label for="oracle-change">Describe your change</label>
          <textarea id="oracle-change" name="change" required maxlength="${ORACLE_CHANGE_MAX_LENGTH}"></textarea>
          <p class="hint">Up to ${ORACLE_CHANGE_MAX_LENGTH.toLocaleString('en-US')} characters. Your description replaces the placeholder below.</p>
          <pre aria-label="Prompt preview">${escapeHtml(oracleBuildPrompt(slug))}</pre>
          <div class="actions"><button class="submit" type="submit">Open in Oracle</button></div>
        </form>
      </details>
    </section>`;
}

export function renderLandingPage(config: AppConfig): string {
  const name = escapeHtml(config.appName);
  const env = escapeHtml(config.environment);
  const repo = repoUrl(config.githubOrg, config.appName);
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${name}</title>
  <style>${STYLES}</style>
</head>
<body>
  <header>
    <img src="${PERSONA_LOGO_URL}" alt="Persona">
    <span class="product">Frontier</span>
  </header>
  <main>
    <h1>${name}</h1>
    <p class="lede">A Frontier app, running. Replace this page with your own.</p>
    ${buildInOracle(config)}
    <section class="card">
      <h2>This deployment</h2>
      <dl>
        <dt>App</dt><dd>${name}</dd>
        <dt>Environment</dt><dd>${env}</dd>
        <dt>Datadog service</dt><dd>${escapeHtml(config.ddService)}</dd>
      </dl>
    </section>
    <section class="card">
      <h2>Links</h2>
      <ul>
        <li><a href="${escapeHtml(datadogApmUrl(config.ddService, config.environment))}">Datadog APM</a>: traces for this service in ${env}</li>
        <li><a href="${escapeHtml(readmeUrl(config.githubOrg, config.appName))}">README</a>: how this app is built, run and deployed</li>
        <li><a href="${escapeHtml(repo)}">GitHub repository</a></li>
        <li><a href="${FRONTIER_USAGE_URL}">go/frontier-usage</a>: Frontier setup, configuration and FAQ</li>
        <li><a href="${FRONTIER_CONFIG_REFERENCE_URL}">frontier-app-base config.libsonnet</a>: every deploy option and its default</li>
      </ul>
    </section>
  </main>
</body>
</html>
`;
}
