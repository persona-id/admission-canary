// expect: must be forge/<forge-app> or start with spiffe://
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { routes: [{ paths: ['/*'], humans: 'none', principals: ['forge/Not_Valid'] }] }))
