local cfg = import '../../config.libsonnet';
local mysqlDatabase = import '../../lib/mysqldatabase.libsonnet';

local app(namespace, instance={}, deletionPolicy='abandon', extra={}) = mysqlDatabase.app(cfg {
  appName: namespace,
  namespace: 'frontier-' + namespace,
  mysql+: {
    enabled: true,
    projectId: 'persona-frontier-staging',
    instance+: instance { deletionPolicy: deletionPolicy },
  } + extra,
});

local defaultProject(namespace) = mysqlDatabase.app(cfg {
  appName: namespace,
  namespace: 'frontier-' + namespace,
  mysql+: { enabled: true },
}).instance.metadata.annotations['cnrm.cloud.google.com/project-id'];

local grown = app('demo-prod', { tier: 'db-custom-2-7680', availabilityType: 'REGIONAL', diskSize: 50 }, extra={
  collation: 'utf8mb4_unicode_ci',
  databases: [{ name: 'reporting' }],
  users: [{ name: 'billing-reader', type: 'CLOUD_IAM_USER', email: 'reader@withpersona.com' }],
});

{
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: 'mysql-environment-profiles-test' },
  data: {
    development: app('demo-dev').instance.spec.settings.availabilityType,
    developmentTier: app('demo-dev').instance.spec.settings.tier,
    developmentDisk: std.toString(app('demo-dev').instance.spec.settings.diskSize),
    developmentVersion: app('demo-dev').instance.spec.databaseVersion,
    production: app('demo-prod').instance.spec.settings.availabilityType,
    productionTier: app('demo-prod').instance.spec.settings.tier,
    productionDisk: std.toString(app('demo-prod').instance.spec.settings.diskSize),
    grownAvailability: grown.instance.spec.settings.availabilityType,
    grownTier: grown.instance.spec.settings.tier,
    grownDisk: std.toString(grown.instance.spec.settings.diskSize),
    grownCollation: grown.database.spec.collation,
    extraDatabase: grown.extraDatabases.reporting.spec.resourceID,
    extraUser: grown.extraUsers['billing-reader'].spec.resourceID,
    extraUserType: grown.extraUsers['billing-reader'].spec.type,
    developmentProject: defaultProject('demo-dev'),
    productionProject: defaultProject('demo-prod'),

    // ConfigMap data must be strings for kubeconform.
    abandonAnnotation: std.manifestJsonMinified(app('demo-prod').instance.metadata.annotations),
    abandonDeletionProtection: std.toString(app('demo-prod').instance.spec.settings.deletionProtectionEnabled),
    deleteAnnotation: std.manifestJsonMinified(app('demo-prod', deletionPolicy='delete').instance.metadata.annotations),
    deleteDeletionProtection: std.toString(app('demo-prod', deletionPolicy='delete').instance.spec.settings.deletionProtectionEnabled),
  },
}
