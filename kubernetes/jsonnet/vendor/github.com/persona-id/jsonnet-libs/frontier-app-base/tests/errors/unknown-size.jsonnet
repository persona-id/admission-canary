// expect: valid sizes are small, medium and large
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { backgroundJobs: { enabled: true, workers: [{ name: 'w', size: 'huge' }] } }))
