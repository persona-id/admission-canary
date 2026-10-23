// visibility: none, reachable only by the apps a route lists.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-dev',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  visibility: 'none',
  routes: [{ paths: ['/*'], humans: 'none', frontierApps: ['frontier-other-dev'] }],
}))
