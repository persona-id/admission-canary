// expect: mysql.privateNetwork is always projects/persona-frontier-staging/global/networks/default on Frontier. Remove mysql.privateNetwork.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'other-vpc',
  namespace: 'frontier-other-vpc-dev',
  gcpProject: 'persona-frontier-staging',
  permissions: { owner: 'owner' },
  mysql: {
    enabled: true,
    privateNetwork: 'projects/persona-frontier-staging/global/networks/other',
  },
}))
