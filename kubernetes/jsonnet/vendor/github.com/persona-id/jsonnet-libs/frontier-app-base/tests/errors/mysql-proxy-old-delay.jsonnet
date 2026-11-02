// expect: mysql.proxy.maxSigtermDelay is now mysql.proxy.shutdownDelaySeconds, a number of seconds.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'old-delay',
  namespace: 'frontier-old-delay-dev',
  gcpProject: 'persona-frontier-staging',
  permissions: { owner: 'owner' },
  mysql: { enabled: true, proxy: { maxSigtermDelay: '30s' } },
}))
