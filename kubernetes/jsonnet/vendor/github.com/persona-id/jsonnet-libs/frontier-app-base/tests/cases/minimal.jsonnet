// The chart's CI values: nothing but the required settings.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'gha-ci',
  namespace: 'demo-dev',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
}))
