// expect: singleInstance means exactly one copy
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { backgroundJobs: { enabled: true, workers: [{ name: 'w', singleInstance: true, replicas: 2 }] } }))
