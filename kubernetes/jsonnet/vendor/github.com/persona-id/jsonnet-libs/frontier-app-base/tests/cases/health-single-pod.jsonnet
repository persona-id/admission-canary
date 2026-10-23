// The budget is not rendered with one pod kept running, even when enabled.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-dev',
  permissions: { owner: 'owner' },
  image: { repository: 'r', tag: 't' },
  podDisruptionBudget: { enabled: true },
}))
