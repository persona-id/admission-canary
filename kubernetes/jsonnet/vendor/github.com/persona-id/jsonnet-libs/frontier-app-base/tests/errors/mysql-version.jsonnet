// expect: mysql.version must be MYSQL_8_0 or MYSQL_8_4, not "MYSQL_5_7".
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'old-mysql',
  namespace: 'frontier-old-mysql-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    version: 'MYSQL_5_7',
  },
}))
