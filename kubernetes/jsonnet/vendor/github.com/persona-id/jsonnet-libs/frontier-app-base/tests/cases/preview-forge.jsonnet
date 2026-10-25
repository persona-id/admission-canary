// A preview of a dev app with Forge callers and a PodDisruptionBudget.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.preview({
  appName: 'demo-dev',
  namespace: 'frontier-demo-dev',
  permissions: { owner: 'owner' },
  image: { repository: 'r', tag: 't' },
  podDisruptionBudget: { enabled: true },
  scaling: { minScale: 2 },
  routes: [
    { paths: ['/mcp/*'], humans: 'none', principals: ['forge/oracle'] },
    { paths: ['/*'], humans: 'okta' },
  ],
}, 7))
