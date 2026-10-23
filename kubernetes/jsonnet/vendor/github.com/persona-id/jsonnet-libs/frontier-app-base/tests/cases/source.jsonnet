// Deploy source provenance on every workload: annotations that win a clash with a
// workload's own, DD_GIT_* env that explicit env overrides, and `dirty: false` kept.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-dev',
  permissions: { owner: 'owner' },
  image: { repository: 'ghcr.io/persona-id/demo', tag: 'abc123' },
  source: {
    repository: 'https://github.com/persona-id/demo',
    // SHA-256, too long for a label.
    revision: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    dirty: false,
  },
  env: [{ name: 'DD_GIT_COMMIT_SHA', value: 'override' }],
  backgroundJobs: {
    enabled: true,
    workers: [{
      name: 'consumer',
      annotations: { custom: 'worker', 'org.opencontainers.image.revision': 'wrong' },
      env: [{ name: 'DD_GIT_COMMIT_SHA', value: 'worker-override' }],
    }],
    scheduled: [{
      name: 'nightly',
      schedule: '0 2 * * *',
      annotations: { custom: 'job', 'org.opencontainers.image.revision': 'wrong' },
    }],
  },
}))
