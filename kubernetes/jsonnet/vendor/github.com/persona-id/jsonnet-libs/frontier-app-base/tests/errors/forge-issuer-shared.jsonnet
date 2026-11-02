// expect: forgeIdentity.issuers must each have their own issuer.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { forgeIdentity: { issuers: { 'forge-external': { issuer: 'https://persona-cf-app-forge-identity-prod.persona-app.workers.dev' } } } }))
