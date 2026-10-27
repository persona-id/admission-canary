// expect: mysql.databases name "mysql" must be a lowercase name
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-db',
  namespace: 'frontier-bad-db-dev',
  permissions: { owner: 'owner' },
  mysql: {
    enabled: true,
    projectId: 'persona-frontier-staging',
    databases: [{ name: 'mysql' }],
  },
}))
