// expect: namespace is required
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo' }))
