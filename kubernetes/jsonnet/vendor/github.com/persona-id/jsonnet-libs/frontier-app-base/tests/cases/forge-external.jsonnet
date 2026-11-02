// Forge callers from both Cloudflare accounts: the same name under each prefix is
// a different caller, each admitted only with its own signer's pass.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  routes: [
    { paths: ['/partner/*'], humans: 'none', principals: ['forge-external/partner-app', 'forge-external/oracle'] },
    { paths: ['/mcp/*'], humans: 'none', principals: ['forge-internal/oracle'] },
  ],
}))
