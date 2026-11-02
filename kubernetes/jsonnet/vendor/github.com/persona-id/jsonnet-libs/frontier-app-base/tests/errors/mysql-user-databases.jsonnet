// expect: mysql.users databases for "reader" must list databases on this instance: bad-db-grant.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-db-grant',
  namespace: 'frontier-bad-db-grant-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    users: [{ name: 'reader', type: 'CLOUD_IAM_USER', email: 'reader@withpersona.com', databases: ['mysql'] }],
  },
}))
