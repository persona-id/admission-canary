// expect: mysql.enabled cannot be combined with gcpServiceAccount.enabled
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'custom-identity',
  namespace: 'frontier-custom-identity-dev',
  permissions: { owner: 'owner' },
  gcpServiceAccount: { enabled: true },
  mysql: {
    enabled: true,
    projectId: 'persona-frontier-staging',
  },
}))
