// expect: mysql.databases names must be unique, counting "_" and "-" as the same.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'clash',
  namespace: 'frontier-clash-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    databaseName: 'clash_dev',
    databases: [{ name: 'clash-dev' }],
  },
}))
