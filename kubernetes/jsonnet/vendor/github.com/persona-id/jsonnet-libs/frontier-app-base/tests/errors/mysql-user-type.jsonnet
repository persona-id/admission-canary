// expect: mysql.users type for "reader" must be CLOUD_IAM_USER, CLOUD_IAM_SERVICE_ACCOUNT or CLOUD_IAM_GROUP
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-user',
  namespace: 'frontier-bad-user-dev',
  permissions: { owner: 'owner' },
  mysql: {
    enabled: true,
    projectId: 'persona-frontier-staging',
    users: [{ name: 'reader', type: 'BUILTIN', email: 'reader@withpersona.com' }],
  },
}))
