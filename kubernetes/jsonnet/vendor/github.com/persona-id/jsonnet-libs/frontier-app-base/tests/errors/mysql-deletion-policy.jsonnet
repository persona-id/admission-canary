// expect: mysql.instance.deletionPolicy must be abandon or delete, not "drop"
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-deletion-policy',
  namespace: 'frontier-bad-deletion-policy-dev',
  permissions: { owner: 'owner' },
  mysql: {
    enabled: true,
    projectId: 'persona-frontier-staging',
    instance: { deletionPolicy: 'drop' },
  },
}))
