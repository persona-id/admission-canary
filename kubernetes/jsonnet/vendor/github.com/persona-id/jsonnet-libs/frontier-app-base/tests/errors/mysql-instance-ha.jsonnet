// expect: mysql.instance.tier db-g1-small cannot be REGIONAL
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-ha',
  namespace: 'frontier-bad-ha-dev',
  permissions: { owner: 'owner' },
  mysql: {
    enabled: true,
    projectId: 'persona-frontier-staging',
    instance: { availabilityType: 'REGIONAL' },
  },
}))
