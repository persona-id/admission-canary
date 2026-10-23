import express, { type Express } from 'express';
import type { AppConfig } from './config.js';
import { repoUrl } from './links.js';
import { isInternal, oracleChatUrl } from './oracle.js';
import { BUILD_IN_ORACLE_PATH, renderLandingPage } from './page.js';

export function createApp(config: AppConfig): Express {
  const app = express();
  app.disable('x-powered-by');

  // Knative's readiness probe and frontier-app-base's open /healthz route.
  app.get('/healthz', (_req, res) => {
    res.type('text/plain').send('ok');
  });

  app.get('/', (_req, res) => {
    res.type('html').send(renderLandingPage(config));
  });

  // The Build in Oracle form submits here; the redirect target is always
  // oracle.withpersona.ai, built by oracleChatUrl from this app's own repo.
  app.get(BUILD_IN_ORACLE_PATH, (req, res) => {
    const change = typeof req.query.change === 'string' ? req.query.change : '';
    const url = isInternal(config.visibility) ? oracleChatUrl(repoUrl(config.githubOrg, config.appName), change) : null;
    if (!url) {
      res.status(404).type('text/plain').send('Not found');
      return;
    }
    res.redirect(302, url);
  });

  return app;
}
