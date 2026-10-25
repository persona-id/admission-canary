// What a preview gets from a dev app with no buckets or Secrets: nothing.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.previewAccess({
  appName: 'demo-dev',
  namespace: 'frontier-demo-dev',
  permissions: { owner: 'owner' },
  image: { repository: 'r', tag: 't' },
}, 7))
