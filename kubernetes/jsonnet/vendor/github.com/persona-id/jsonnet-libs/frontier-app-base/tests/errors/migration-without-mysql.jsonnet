// expect: mysql.migration runs against the app database
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { mysql: { enabled: false, migration: { enabled: true, command: ['migrate'] } } }))
