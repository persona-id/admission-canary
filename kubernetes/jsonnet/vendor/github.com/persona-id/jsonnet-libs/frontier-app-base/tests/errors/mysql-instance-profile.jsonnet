// expect: mysql.instance.profile has been replaced by tier and availabilityType
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-profile',
  namespace: 'frontier-bad-profile-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    instance: { profile: 'regional-ha' },
  },
}))
