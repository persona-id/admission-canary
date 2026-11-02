// expect: mysql.databaseName "trail_" must be a lowercase name of letters, digits, dashes and underscores
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'trail',
  namespace: 'frontier-trail-dev',
  permissions: { owner: 'owner' },
  gcpProject: 'persona-frontier-staging',
  mysql: { enabled: true, databaseName: 'trail_' },
}))
