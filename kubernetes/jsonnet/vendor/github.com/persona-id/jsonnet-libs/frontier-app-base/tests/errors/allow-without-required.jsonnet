// expect: they are ignored
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { auth: { allow: { groups: ['G'] } } }))
