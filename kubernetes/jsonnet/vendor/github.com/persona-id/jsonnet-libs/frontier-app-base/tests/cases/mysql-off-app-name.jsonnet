// MySQL off: an appName that isn't a valid MySQL database name still renders,
// since nothing creates a database for it.
local frontier = import '../../main.libsonnet';

local objects = frontier.toList(frontier.new({
  appName: 'My.App',
  namespace: 'frontier-my-app-dev',
  permissions: { owner: 'owner' },
}));

{
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: 'mysql-off-app-name-test' },
  data: { rendered: std.toString(std.length(objects) > 0) },
}
