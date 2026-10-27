local cfg = import '../../config.libsonnet';
local mysqlDatabase = import '../../lib/mysqldatabase.libsonnet';

local app(namespace, profile='environment-default', deletionPolicy='abandon') = mysqlDatabase.app(cfg {
  appName: namespace,
  namespace: 'frontier-' + namespace,
  mysql+: {
    enabled: true,
    projectId: 'persona-frontier-staging',
    instance+: { profile: profile, deletionPolicy: deletionPolicy },
  },
});

local defaultProject(namespace) = mysqlDatabase.app(cfg {
  appName: namespace,
  namespace: 'frontier-' + namespace,
  mysql+: { enabled: true },
}).instance.metadata.annotations['cnrm.cloud.google.com/project-id'];

{
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: 'mysql-environment-profiles-test' },
  data: {
    development: app('demo-dev').instance.spec.settings.availabilityType,
    developmentTier: app('demo-dev').instance.spec.settings.tier,
    production: app('demo-prod').instance.spec.settings.availabilityType,
    productionTier: app('demo-prod').instance.spec.settings.tier,
    productionZonalOverride: app('demo-prod', 'zonal').instance.spec.settings.availabilityType,
    productionZonalOverrideTier: app('demo-prod', 'zonal').instance.spec.settings.tier,
    productionRegionalHaOverride: app('demo-prod', 'regional-ha').instance.spec.settings.availabilityType,
    productionRegionalHaOverrideTier: app('demo-prod', 'regional-ha').instance.spec.settings.tier,
    productionLargeOverride: app('demo-prod', 'regional-ha-large').instance.spec.settings.availabilityType,
    productionLargeOverrideTier: app('demo-prod', 'regional-ha-large').instance.spec.settings.tier,
    developmentProject: defaultProject('demo-dev'),
    productionProject: defaultProject('demo-prod'),

    // ConfigMap data must be strings for kubeconform.
    abandonAnnotation: std.manifestJsonMinified(app('demo-prod').instance.metadata.annotations),
    abandonDeletionProtection: std.toString(app('demo-prod').instance.spec.settings.deletionProtectionEnabled),
    deleteAnnotation: std.manifestJsonMinified(app('demo-prod', deletionPolicy='delete').instance.metadata.annotations),
    deleteDeletionProtection: std.toString(app('demo-prod', deletionPolicy='delete').instance.spec.settings.deletionProtectionEnabled),
  },
}
