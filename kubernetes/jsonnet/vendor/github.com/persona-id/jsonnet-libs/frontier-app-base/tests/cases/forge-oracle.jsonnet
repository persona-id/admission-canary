// What every Frontier app's routes name today: Oracle, as `forge/persona-cf-app-oracle`
// (the deprecated alias). persona-frontier-gateway signs Oracle's passes with
// `sub: persona-cf-app-oracle` and `forge_environment: production`, the pair this
// renders, for both its service calls and its delegated ones. The discovery label
// stays on.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  routes: [
    { paths: ['/mcp/*'], humans: 'none', principals: ['forge/persona-cf-app-oracle'] },
    { paths: ['/*'], humans: 'okta' },
  ],
  delegatedCallers: ['forge/persona-cf-app-oracle'],
}))
