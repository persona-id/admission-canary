// expect: mysql.instance.profile must be environment-default, zonal, regional-ha-small, regional-ha or regional-ha-large
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-profile',
  namespace: 'frontier-bad-profile-dev',
  permissions: { owner: 'owner' },
  mysql: {
    enabled: true,
    projectId: 'persona-frontier-staging',
    instance: { profile: 'custom' },
  },
}))
