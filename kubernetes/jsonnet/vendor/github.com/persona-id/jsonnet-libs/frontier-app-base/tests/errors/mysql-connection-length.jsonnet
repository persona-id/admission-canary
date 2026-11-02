// expect: mysql.connections name "readonly" is too long: app-a-long-app-name-prod-readonly must fit 30 characters.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'a-long-app-name',
  namespace: 'frontier-a-long-app-name-prod',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    connections: [{ name: 'readonly' }],
  },
}))
