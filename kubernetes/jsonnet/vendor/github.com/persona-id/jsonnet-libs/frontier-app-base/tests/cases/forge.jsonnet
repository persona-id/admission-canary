// Forge callers named by route: the pass verification and Forge listener route,
// a Forge rule beside an open and an Okta allowlist route, and humans rules that
// refuse pass holders.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  routes: [
    { paths: ['/mcp/*'], humans: 'none', principals: ['forge/oracle', 'forge/oracle', 'forge/other-app'] },
    { paths: ['/admin/*'], humans: 'okta', groups: ['Role-Security'], emails: ['a@withpersona.com'] },
    { paths: ['/*'], humans: 'anyone', principals: ['forge/oracle'] },
  ],
}))
