// expect: only rendered when backgroundJobs.enabled is true
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { backgroundJobs: { workers: [{ name: 'w' }] } }))
