// expect: mysql.instance.tier db-g1-small cannot be REGIONAL
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-ha',
  namespace: 'frontier-bad-ha-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    instance: { availabilityType: 'REGIONAL' },
  },
}))
