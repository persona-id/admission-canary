// expect: a preview is rendered from the development config, whose namespace ends in -dev; got "frontier-demo-prod"
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.preview({
  appName: 'demo-prod',
  namespace: 'frontier-demo-prod',
  permissions: { owner: 'owner' },
  image: { repository: 'r', tag: 't' },
}, 1))
