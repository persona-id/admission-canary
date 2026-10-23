// expect: mysql.migration.enabled needs mysql.migration.command
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { mysql: { enabled: true, migration: { enabled: true } } }))
