// Config for this app's production deployment, merged over common/config.libsonnet.
// All available options: https://github.com/persona-id/jsonnet-libs/blob/main/frontier-app-base/config.libsonnet
local app = import '../common/app.libsonnet';
local common = import '../common/config.libsonnet';

{
  appName: app.name + '-prod',

  // Lists replace on merge, so this extends common's env rather than dropping it.
  env: common.env + [
    { name: 'DD_ENV', value: 'production' },
  ],

  // Also the Application's spec.destination.namespace: kubernetes/deploy/production.jsonnet
  // reads it from here. The `-prod` suffix marks the app as production.
  namespace: 'frontier-' + app.name + '-prod',

  // The Application's name, which kubernetes/deploy/production.jsonnet reads from
  // here, and the `app.kubernetes.io/instance` label. ArgoCD tracks resources by
  // the Application's name, in their argocd.argoproj.io/tracking-id annotation, not
  // by this label. Changing it replaces the Application: the old one is pruned,
  // and its finalizer deletes everything it deployed before the new one redeploys.
  releaseName: 'frontier-' + app.name + '-prod',

  managedBy: 'argocd',

  // The tag is not set here. It is the imageTag top-level argument, the
  // release commit sha that kubernetes/deploy/production.jsonnet passes in.
  image: {
    repository: app.imageRepository,
  },

  mysql: {
    enabled: true,
    // This namespace ends in -prod, which would select the persona-frontier
    // project. The canary production app runs on the staging cluster.
    projectId: 'persona-frontier-staging',
    // The other collation from dev, on the app database. The extra database
    // uses utf8mb4_0900_ai_ci.
    collation: 'utf8mb4_unicode_ci',
    databases: [
      { name: 'audit', collation: 'utf8mb4_0900_ai_ci' },
    ],
    users: [
      { name: 'reader', type: 'CLOUD_IAM_USER', email: 'chaitanya.prasad@withpersona.com' },
      {
        name: 'dev-app',
        type: 'CLOUD_IAM_SERVICE_ACCOUNT',
        email: 'app-admission-canary-dev@persona-frontier-staging.iam.gserviceaccount.com',
      },
    ],
    instance: {
      // Larger machine, high availability kept. Disk is already 100 GB.
      tier: 'db-custom-4-15360',
      availabilityType: 'REGIONAL',
      diskSize: 100,
      diskAutoresizeLimit: 100,
    },
  },
}
