local cfg = import '../../config.libsonnet';
local mysqlDatabase = import '../../lib/mysqldatabase.libsonnet';

local app(namespace, profile='environment-default') = mysqlDatabase.app(cfg {
  appName: namespace,
  namespace: 'frontier-' + namespace,
  mysql+: {
    enabled: true,
    projectId: 'persona-frontier-staging',
    instance+: { profile: profile },
  },
});

{
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: 'mysql-environment-profiles-test' },
  data: {
    development: app('demo-dev').instance.spec.settings.availabilityType,
    production: app('demo-prod').instance.spec.settings.availabilityType,
    productionZonalOverride: app('demo-prod', 'zonal').instance.spec.settings.availabilityType,
  },
}
