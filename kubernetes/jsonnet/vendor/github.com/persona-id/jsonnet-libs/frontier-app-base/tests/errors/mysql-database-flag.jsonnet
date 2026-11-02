// expect: mysql.instance.databaseFlags "local_infile" must be one of
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'bad-flag',
  namespace: 'frontier-bad-flag-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
    instance: { databaseFlags: [{ name: 'local_infile', value: 'on' }] },
  },
}))
