// expect: mysql.users privileges for "reader" must be ["ALL PRIVILEGES"] or a list of
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-grant',
  namespace: 'frontier-bad-grant-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    users: [{ name: 'reader', type: 'CLOUD_IAM_USER', email: 'reader@withpersona.com', privileges: ['SUPER'] }],
  },
}))
