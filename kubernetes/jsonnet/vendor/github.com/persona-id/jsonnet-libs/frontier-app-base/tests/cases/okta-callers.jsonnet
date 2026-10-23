// Okta routes that also admit listed callers: those callers skip Okta on the
// app's in-cluster names, and people are admitted only on the gateway hostnames.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  routes: [
    { paths: ['/admin/*'], humans: 'okta', groups: ['Role-Security'], frontierApps: ['frontier-a-prod'] },
    { paths: ['/api/*'], humans: 'okta', principals: ['forge/oracle'] },
    { paths: ['/*'], humans: 'okta' },
  ],
}))
