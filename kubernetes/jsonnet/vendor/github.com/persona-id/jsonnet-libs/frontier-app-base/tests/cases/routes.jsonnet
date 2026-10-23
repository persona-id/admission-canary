// Access by `routes`: machine callers, a public webhook, an Okta allowlist and a
// default Okta route, with minScale raised to 1.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  routes: [
    {
      paths: ['/api/internal/*'],
      humans: 'none',
      frontierApps: ['frontier-a-prod', 'frontier-a-prod'],
      principals: ['forge/oracle', 'spiffe://example.org/ns/x/sa/y'],
    },
    { paths: ['/webhooks'], humans: 'anyone', frontierApps: ['frontier-b-prod'] },
    { paths: ['/admin/*'], humans: 'okta', groups: ['Role-Security'], emails: ['a@withpersona.com'] },
    { paths: ['/*'], humans: 'okta' },
  ],
  scaling: { minScale: 0, maxScale: 3 },
}))
