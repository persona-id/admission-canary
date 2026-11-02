// An app moving from a stack-core Cloud SQL database: its Rails database name,
// collation, flags and size, plus a read-only identity for its replica config.
local frontier = import '../../main.libsonnet';

local objects = frontier.toList(frontier.new({
  appName: 'billing-prod',
  namespace: 'frontier-billing-prod',
  gcpProject: 'persona-frontier',
  permissions: { owner: 'owner' },
  mongo: { enabled: false },
  mysql: {
    enabled: true,
    databaseName: 'billing_production',
    collation: 'utf8mb4_unicode_ci',
    connections: [{ name: 'ro' }],
    instance: {
      tier: 'db-custom-2-7680',
      availabilityType: 'REGIONAL',
      diskSize: 100,
      diskAutoresizeLimit: 100,
      databaseFlags: [
        { name: 'binlog_row_image', value: 'minimal' },
        { name: 'innodb_autoinc_lock_mode', value: '2' },
        { name: 'innodb_cloudsql_managed_buffer_pool', value: 'on' },
        { name: 'innodb_cloudsql_managed_buffer_pool_threshold_pct', value: '90' },
        { name: 'log_bin_trust_function_creators', value: 'on' },
        { name: 'log_output', value: 'FILE' },
        { name: 'long_query_time', value: '2' },
        { name: 'performance_schema', value: 'on' },
        { name: 'performance_schema_max_thread_instances', value: '2048' },
        { name: 'slow_query_log', value: 'on' },
        { name: 'table_open_cache_instances', value: '4' },
      ],
    },
  },
}));

[o for o in objects if std.member(['SQLInstance', 'SQLDatabase', 'ConfigMap'], o.kind) || (o.kind == 'Job' && std.endsWith(o.metadata.name, '-grants'))]
