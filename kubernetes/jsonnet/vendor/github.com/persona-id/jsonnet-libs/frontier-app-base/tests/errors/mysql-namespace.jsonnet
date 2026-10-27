// expect: mysql.enabled requires a frontier-* namespace of at most 35 characters so the generated service account id fits.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'long-namespace',
  namespace: 'frontier-mysql-namespace-too-long-dev',
  permissions: { owner: 'owner' },
  mysql: {
    enabled: true,
    projectId: 'persona-frontier-staging',
  },
}))
