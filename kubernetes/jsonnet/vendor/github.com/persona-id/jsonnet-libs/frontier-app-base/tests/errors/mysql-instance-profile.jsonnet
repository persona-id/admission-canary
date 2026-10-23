// expect: mysql.instance.profile must be environment-default, zonal or regional-ha
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
