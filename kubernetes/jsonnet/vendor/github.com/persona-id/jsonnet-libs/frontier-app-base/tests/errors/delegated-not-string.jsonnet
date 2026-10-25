// expect: delegatedCallers entries must be forge/<clientId>
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { routes: [{ paths: ['/*'], humans: 'okta' }], delegatedCallers: [true] }))
