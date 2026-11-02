// expect: mysql.region is always us-central1 on Frontier. Remove mysql.region.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'missing-region',
  namespace: 'frontier-missing-region-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    region: 'us-east1',
  },
}))
