// expect: delegatedCallers must be a list of forge-internal/<forge-app> entries.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { routes: [{ paths: ['/*'], humans: 'okta' }], delegatedCallers: 'forge/oracle' }))
