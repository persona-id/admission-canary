// expect: is used more than once
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { backgroundJobs: { enabled: true, workers: [{ name: 'a_b' }], scheduled: [{ name: 'A-B', schedule: '* * * * *' }] } }))
