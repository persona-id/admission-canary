// expect: gcsStorageBuckets appPermissions "roles/storage.objectAdmin" cannot be granted to a preview environment
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.previewAccess({
  appName: 'demo-dev',
  namespace: 'frontier-demo-dev',
  permissions: { owner: 'owner' },
  image: { repository: 'r', tag: 't' },
  gcsStorageBuckets: [{ name: 'files', appPermissions: 'roles/storage.objectAdmin' }],
}, 1))
