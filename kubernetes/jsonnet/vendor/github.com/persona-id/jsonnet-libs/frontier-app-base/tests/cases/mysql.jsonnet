// MySQL without Mongo, with a migration and a worker and scheduled job that need the proxy.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'persona-billing-prod',
  namespace: 'frontier-persona-billing-prod',
  permissions: { owner: 'owner' },
  mongo: { enabled: false },
  mysql: {
    enabled: true,
    projectId: 'persona-frontier-staging',
    migration: { enabled: true, command: ['bin/run-migrations'] },
  },
  backgroundJobs: {
    enabled: true,
    workers: [{ name: 'sidekiq', command: ['bundle', 'exec', 'sidekiq'] }],
    scheduled: [{ name: 'nightly', schedule: '0 3 * * *', command: ['bin/rails', 'runner', 'Nightly.run'] }],
  },
}))
