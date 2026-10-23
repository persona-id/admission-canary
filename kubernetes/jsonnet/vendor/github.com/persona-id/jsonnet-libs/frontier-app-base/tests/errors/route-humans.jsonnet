// expect: humans must be none, anyone or okta
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { routes: [{ paths: ['/*'] }] }))
