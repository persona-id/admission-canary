// expect: needs a schedule
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { backgroundJobs: { enabled: true, scheduled: [{ name: 'j' }] } }))
