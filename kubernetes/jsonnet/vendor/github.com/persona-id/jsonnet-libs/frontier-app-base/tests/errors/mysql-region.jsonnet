// expect: mysql.region is required when mysql.enabled is true.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'missing-region',
  namespace: 'frontier-missing-region-dev',
  permissions: { owner: 'owner' },
  mysql: {
    enabled: true,
    projectId: 'persona-frontier-staging',
    region: '',
  },
}))
