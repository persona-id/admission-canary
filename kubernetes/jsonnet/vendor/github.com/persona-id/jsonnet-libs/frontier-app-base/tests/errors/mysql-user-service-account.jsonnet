// expect: mysql.users email for "foreign" must be @withpersona.com, or a service account in persona-frontier-staging.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-user',
  namespace: 'frontier-bad-user-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    users: [{ name: 'foreign', type: 'CLOUD_IAM_SERVICE_ACCOUNT', email: 'foreign@other-project.iam.gserviceaccount.com' }],
  },
}))
