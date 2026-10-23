// A job queue on its own compute class and priority: a Hyperdisk claim under its own
// name, the class's toleration but none of the app's, and the app's compute class
// left alone.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  image: { repository: 'r', tag: 't' },
  computeClass: 'standard-highcpu',
  tolerations: [{ key: 'other', operator: 'Exists', effect: 'NoSchedule' }],
  jobQueue: {
    enabled: true,
    client: 'asynq',
    computeClass: 'standard',
    priorityClassName: 'product-feature',
  },
}))
