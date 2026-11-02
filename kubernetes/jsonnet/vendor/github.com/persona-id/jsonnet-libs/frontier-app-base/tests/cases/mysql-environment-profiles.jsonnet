local cfg = import '../../config.libsonnet';
local mysqlDatabase = import '../../lib/mysqldatabase.libsonnet';

local app(namespace, instance={}, deletionPolicy='abandon', extra={}) = mysqlDatabase.app(cfg {
  appName: namespace,
  namespace: 'frontier-' + namespace,
  gcpProject: 'persona-frontier-staging',
  mysql+: {
    enabled: true,
    instance+: instance { deletionPolicy: deletionPolicy },
  } + extra,
});

local defaultProject(namespace) = mysqlDatabase.app(cfg {
  appName: namespace,
  namespace: 'frontier-' + namespace,
  mysql+: { enabled: true },
});

// What Argo CD renders on each cluster: gcpProject comes from the cluster.
local onCluster(namespace, gcpProject) = mysqlDatabase.app(cfg {
  appName: namespace,
  namespace: 'frontier-' + namespace,
  gcpProject: gcpProject,
  mysql+: { enabled: true },
});

local grown = app('demo-prod', { tier: 'db-custom-2-7680', availabilityType: 'REGIONAL', diskSize: 50 }, extra={
  collation: 'utf8mb4_unicode_ci',
  databases: [{ name: 'reporting' }],
  users: [
    { name: 'billing-reader', type: 'CLOUD_IAM_USER', email: 'reader@withpersona.com' },
    { name: 'reporter', type: 'CLOUD_IAM_SERVICE_ACCOUNT', email: 'reporter@persona-frontier-staging.iam.gserviceaccount.com', privileges: ['SELECT', 'INSERT'], databases: ['reporting'] },
  ],
});
local grownGrantSql = grown.grantJob.spec.template.spec.containers[0].env[0].value;

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
    // Turning on a standby alone keeps production's dedicated default tier.
    productionRegionalTier: app('demo-prod', { availabilityType: 'REGIONAL' }).instance.spec.settings.tier,
    // An explicit tier is kept, even shared-core in production.
    productionSharedCoreTier: app('demo-prod', { tier: 'db-g1-small' }).instance.spec.settings.tier,
    mysql84: app('demo-dev', extra={ version: 'MYSQL_8_4' }).instance.spec.databaseVersion,
    stagingClusterProject: onCluster('demo-dev', 'persona-frontier-staging').instance.metadata.annotations['cnrm.cloud.google.com/project-id'],
    stagingClusterNetwork: onCluster('demo-dev', 'persona-frontier-staging').instance.spec.settings.ipConfiguration.privateNetworkRef.external,
    stagingClusterWorkloadIdentity: onCluster('demo-dev', 'persona-frontier-staging').iamPolicy.spec.bindings[0].members[0],
    stagingClusterConnection: onCluster('demo-dev', 'persona-frontier-staging').connection.data.instanceConnectionName,
    stagingClusterEnvironment: onCluster('demo-prod', 'persona-frontier-staging').instance.metadata.labels.environment,
    productionClusterProject: onCluster('demo-prod', 'persona-frontier').instance.metadata.annotations['cnrm.cloud.google.com/project-id'],
    grantSql: grownGrantSql,
    extraUserAnnotations: std.manifestJsonMinified(grown.extraUsers['billing-reader'].metadata.annotations),
    grownAvailability: grown.instance.spec.settings.availabilityType,
    grownTier: grown.instance.spec.settings.tier,
    grownDisk: std.toString(grown.instance.spec.settings.diskSize),
    grownCollation: grown.database.spec.collation,
    extraDatabase: grown.extraDatabases.reporting.spec.resourceID,
    extraUser: grown.extraUsers['billing-reader'].spec.resourceID,
    extraUserType: grown.extraUsers['billing-reader'].spec.type,
    extraServiceAccount: grown.extraUsers.reporter.spec.resourceID,
    extraUserGrant:
      if std.length(std.findSubstr("TO 'reader'@'%'", grownGrantSql)) > 0 &&
         std.length(std.findSubstr('reader@withpersona.com', grownGrantSql)) == 0
      then 'reader-login'
      else error 'extra IAM users must be granted by their MySQL login',
    // Both environment namespaces run on the same Frontier cluster, so an
    // unpinned dev database must use the production cluster's GCP project.
    developmentProject: defaultProject('demo-dev').instance.metadata.annotations['cnrm.cloud.google.com/project-id'],
    developmentServiceAccountProject: defaultProject('demo-dev').serviceAccount.metadata.annotations['cnrm.cloud.google.com/project-id'],
    developmentWorkloadIdentity: defaultProject('demo-dev').iamPolicy.spec.bindings[0].members[0],
    productionProject: defaultProject('demo-prod').instance.metadata.annotations['cnrm.cloud.google.com/project-id'],

    // ConfigMap data must be strings for kubeconform.
    abandonAnnotation: std.manifestJsonMinified(app('demo-prod').instance.metadata.annotations),
    abandonDeletionProtection: std.toString(app('demo-prod').instance.spec.settings.deletionProtectionEnabled),
    deleteAnnotation: std.manifestJsonMinified(app('demo-prod', deletionPolicy='delete').instance.metadata.annotations),
    deleteDeletionProtection: std.toString(app('demo-prod', deletionPolicy='delete').instance.spec.settings.deletionProtectionEnabled),
  },
}
