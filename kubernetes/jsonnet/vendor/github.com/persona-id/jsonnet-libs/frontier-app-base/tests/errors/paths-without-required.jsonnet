// expect: only scope the gate
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { auth: { unauthedPaths: ['/a'] } }))
