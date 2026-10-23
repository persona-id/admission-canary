// expect: homestead.catalog must be prod or dev, not "staging".
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' }, homestead: { catalog: 'staging' } }))
