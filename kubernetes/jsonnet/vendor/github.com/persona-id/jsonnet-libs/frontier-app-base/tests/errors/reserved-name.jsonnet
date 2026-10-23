// expect: collides with a name the library already owns
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { backgroundJobs: { enabled: true, workers: [{ name: 'valkey' }] } }))
