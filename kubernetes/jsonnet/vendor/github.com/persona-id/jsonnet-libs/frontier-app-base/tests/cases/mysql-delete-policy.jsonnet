// An instance deleted with its app (deletionPolicy 'delete') still abandons its
// databases: deleting the instance drops them, and Config Connector deletes a
// database through its instance, so a database pruned with the instance would
// wait on it forever.
local frontier = import '../../main.libsonnet';

local objects = frontier.toList(frontier.new({
  appName: 'canary-prod',
  namespace: 'frontier-canary-prod',
  gcpProject: 'persona-frontier',
  permissions: { owner: 'owner' },
  image: { repository: 'r', tag: 't' },
  mysql: {
    enabled: true,
    databases: [{ name: 'audit' }],
    instance: { deletionPolicy: 'delete' },
  },
}));

[o for o in objects if std.member(['SQLInstance', 'SQLDatabase'], o.kind)]
