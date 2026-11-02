// expect: mysql.connections name "prod" must be lowercase letters and digits, and not dev or prod.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'takeover',
  namespace: 'frontier-takeover-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    connections: [{ name: 'prod' }],
  },
}))
