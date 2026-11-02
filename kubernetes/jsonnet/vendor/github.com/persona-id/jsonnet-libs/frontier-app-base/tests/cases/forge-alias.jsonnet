// The deprecated `forge/` prefix is an alias for `forge-internal/`: both name the
// same caller, so a route listing both admits one request principal, and either
// form works for delegation and the Oracle discovery label.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  delegatedCallers: ['forge-internal/persona-cf-app-oracle'],
  routes: [
    { paths: ['/mcp/*'], humans: 'none', principals: ['forge/oracle', 'forge-internal/oracle'] },
    { paths: ['/*'], humans: 'okta' },
  ],
}))
