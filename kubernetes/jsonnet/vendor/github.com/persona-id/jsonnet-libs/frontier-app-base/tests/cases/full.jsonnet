// Every feature at once.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'jane.doe', additionalCollaborators: ['sam', 'alex-r', 'sam'] },
  homestead: { catalog: 'dev' },
  releaseName: 'rel',
  image: { repository: 'ghcr.io/persona-id/demo', tag: 'abc123' },
  visibility: 'public',
  auth: {
    required: true,
    unauthedPaths: ['/webhooks/stripe', '/public/*'],
    allow: { emails: ['a@withpersona.com'], groups: ['Role-Engineering'] },
  },
  backgroundJobs: {
    enabled: true,
    workers: [
      { name: 'sidekiq', command: ['bundle', 'exec', 'sidekiq'], replicas: 2, size: 'medium' },
      {
        name: 'Sync_Job',
        env: [{ name: 'ROLE', value: 'worker' }, { name: 'LOG_LEVEL', value: 'warn' }],
        singleInstance: true,
        terminationGracePeriodSeconds: 60,
        size: 'medium',
        resources: { limits: { memory: '3Gi' } },
        labels: { 'tags.datadoghq.com/service': 'demo-sync', environment: 'hacked' },
        annotations: { 'ad.datadoghq.com/worker.logs': '[{"source":"ruby"}]' },
        computeClass: 'standard-highcpu',
        livenessProbe: { exec: { command: ['test', '-f', '/tmp/ready'] } },
        image: 'postgres:17-alpine',
      },
    ],
    scheduled: [
      {
        name: 'nightly-report',
        schedule: '0 2 * * *',
        command: ['bin/report'],
        args: ['--all'],
        timeZone: 'America/Los_Angeles',
        activeDeadlineSeconds: 3600,
        ttlSecondsAfterFinished: 604800,
        startingDeadlineSeconds: 100,
      },
    ],
  },
  tolerations: [{ key: 'other', operator: 'Exists', effect: 'NoSchedule' }],
  customDomains: [{ fqdn: 'foo.withpersona.app' }],
  env: [{ name: 'LOG_LEVEL', value: 'debug' }, { name: 'NUM', value: 3 }, { name: 'REDIS_URL', value: 'override' }],
  gcsStorageBuckets: [
    {
      name: 'foo_bucket',
      additionalPermissions: {
        'roles/storage.objectUser': ['user:foo@example.com'],
        'roles/storage.objectAdmin': ['user:bar@example.com'],
      },
      versioningEnabled: false,
    },
    { name: 'other', appPermissions: 'roles/storage.objectViewer' },
  ],
  gcpServiceAccount: { enabled: true },
  jobQueue: { enabled: true, client: 'asynq', storageClass: 'premium' },
  mongo: { enabled: true },
  scaling: { minScale: 1, maxScale: 5 },
  secrets: {
    envVars: [{ name: 'SOME_USER', secretKey: 'username', fromSecretName: 'some_secret' }],
    mounts: [{ path: '/secrets/another', fromSecretName: 'another-secret' }],
    sources: {
      onePassword: { items: [{ name: 'some_secret' }, { name: 'another-secret', vaultId: 'v2' }] },
      sealedSecrets: {
        items: [
          { name: 'sealed-one', ciphertext: 'AgB1', envVar: 'SEALED_ONE', mountPath: '/secrets/sealed' },
          {
            name: 'sealed-two',
            ciphertext: 'AgB2',
            envVar: 'SEALED_TWO',
            expiresAt: '2027-01-15',
            updatedAt: '2026-10-14T19:02:11Z',
            updatedBy: 'ada@withpersona.com',
          },
        ],
      },
    },
  },
  serviceAccountTokens: [
    { name: 'oracle-oidc', audience: 'https://oracle.example', mountPath: '/var/run/secrets/tokens/oracle' },
  ],
  valkey: { enabled: true },
}))
