// A Forge principal names an app; `@<environment>` names which of its Workers. A
// bare name is the production Worker. Every Forge rule pins the pass's
// `forge_environment`, one rule per environment, and a delegated caller's too.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  routes: [
    {
      paths: ['/api/*'],
      humans: 'none',
      principals: ['forge-external/onboard', 'forge-external/onboard@staging', 'forge-internal/oracle@production'],
    },
    { paths: ['/*'], humans: 'okta' },
  ],
  delegatedCallers: ['forge-internal/oracle', 'forge-internal/oracle@staging'],
}))
