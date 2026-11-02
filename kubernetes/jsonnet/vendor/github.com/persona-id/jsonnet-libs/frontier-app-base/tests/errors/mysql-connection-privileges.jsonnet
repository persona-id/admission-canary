// expect: mysql.connections privileges for "ro" must be ["ALL PRIVILEGES"] or a list of
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-conn',
  namespace: 'frontier-bad-conn-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    connections: [{ name: 'ro', privileges: ['GRANT OPTION'] }],
  },
}))
