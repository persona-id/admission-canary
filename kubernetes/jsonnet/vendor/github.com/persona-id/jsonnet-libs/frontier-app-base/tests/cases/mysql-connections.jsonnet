// A second, read-only MySQL identity for the app, standing in for a replica,
// plus the InnoDB buffer pool flags, on the production cluster.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'billing-prod',
  namespace: 'frontier-billing-prod',
  gcpProject: 'persona-frontier',
  permissions: { owner: 'owner' },
  mongo: { enabled: false },
  mysql: {
    enabled: true,
    connections: [{ name: 'ro' }],
    instance: {
      databaseFlags: [
        { name: 'innodb_cloudsql_managed_buffer_pool', value: 'on' },
        { name: 'innodb_cloudsql_managed_buffer_pool_threshold_pct', value: '90' },
      ],
    },
  },
}))
