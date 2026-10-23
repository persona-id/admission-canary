// expect: gives them no hostname to use
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { visibility: 'none', routes: [{ paths: ['/*'], humans: 'anyone' }] }))
