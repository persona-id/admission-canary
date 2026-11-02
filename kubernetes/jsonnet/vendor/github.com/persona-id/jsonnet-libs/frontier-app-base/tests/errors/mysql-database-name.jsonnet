// expect: mysql.databases name "mysql" must be a lowercase name
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-db',
  namespace: 'frontier-bad-db-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    databases: [{ name: 'mysql' }],
  },
}))
