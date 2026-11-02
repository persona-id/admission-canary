// expect: must be forge-external/<forge-app>, forge-internal/<forge-app> (optionally @<environment>) or start with spiffe://
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { routes: [{ paths: ['/*'], humans: 'none', principals: ['forge-other/app'] }] }))
