// delegatedCallers on Okta routes, with no route naming a Forge app: the pass
// verification and Forge listener route are still rendered, with the person's
// headers mapped and caller-sent identity headers removed; each Okta route gets a
// rule per allowlist claim, always requiring the marker and a corporate email;
// the humans: none route gets none; Okta is skipped on the in-cluster names only;
// and listing Oracle labels the Knative Service.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  delegatedCallers: ['forge/persona-cf-app-oracle', 'forge/other-app', 'forge/persona-cf-app-oracle'],
  routes: [
    { paths: ['/closed/*'], humans: 'none', frontierApps: ['frontier-a-prod'] },
    { paths: ['/admin/*'], humans: 'okta', groups: ['Role-Security'], emails: ['special@withpersona.com'] },
    { paths: ['/*'], humans: 'okta' },
  ],
}))
