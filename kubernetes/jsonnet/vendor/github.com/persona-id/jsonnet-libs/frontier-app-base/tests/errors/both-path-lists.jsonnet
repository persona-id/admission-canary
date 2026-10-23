// expect: set one or the other
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { auth: { required: true, unauthedPaths: ['/a'], authedPaths: ['/b'] } }))
