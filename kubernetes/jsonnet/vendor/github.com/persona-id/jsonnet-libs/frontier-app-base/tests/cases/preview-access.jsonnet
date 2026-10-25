// What a preview gets from the dev app: its buckets, with the default role and a
// narrower one, and every Secret the app reads, including Mongo's.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.previewAccess({
  appName: 'demo-dev',
  namespace: 'frontier-demo-dev',
  permissions: { owner: 'owner' },
  image: { repository: 'r', tag: 't' },
  gcsStorageBuckets: [
    {
      name: 'foo_bucket',
      additionalPermissions: { 'roles/storage.objectAdmin': ['user:bar@example.com'] },
    },
    { name: 'other', appPermissions: 'roles/storage.objectViewer' },
  ],
  mongo: { enabled: true },
  secrets: {
    envVars: [{ name: 'SOME_USER', secretKey: 'username', fromSecretName: 'some_secret' }],
    mounts: [{ path: '/secrets/another', fromSecretName: 'another-secret' }],
    sources: {
      onePassword: { items: [{ name: 'some_secret' }] },
      sealedSecrets: { items: [{ name: 'sealed-one', ciphertext: 'AgB1', envVar: 'SEALED_ONE' }] },
    },
  },
}, '42'))
