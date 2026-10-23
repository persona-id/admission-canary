// expect: prNumber must be a positive integer, got "07"
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.preview({
  appName: 'demo-dev',
  namespace: 'frontier-demo-dev',
  permissions: { owner: 'owner' },
  image: { repository: 'r', tag: 't' },
}, '07'))
