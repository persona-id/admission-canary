// expect: mysql.instance.deletionPolicy must be abandon or delete, not "drop"
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-deletion-policy',
  namespace: 'frontier-bad-deletion-policy-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    instance: { deletionPolicy: 'drop' },
  },
}))
