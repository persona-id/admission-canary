// Config for this app's development deployment, merged over common/config.libsonnet.
// All available options: https://github.com/persona-id/jsonnet-libs/blob/main/frontier-app-base/config.libsonnet
local app = import '../common/app.libsonnet';
local common = import '../common/config.libsonnet';

{
  appName: app.name + '-dev',

  // Lists replace on merge, so this extends common's env rather than dropping it.
  env: common.env + [
    { name: 'DD_ENV', value: 'development' },
  ],

  // Also the Application's spec.destination.namespace: kubernetes/deploy/development.jsonnet
  // reads it from here.
  namespace: 'frontier-' + app.name + '-dev',

  // The Application's name, which kubernetes/deploy/development.jsonnet reads from
  // here, and the `app.kubernetes.io/instance` label. ArgoCD tracks resources by
  // the Application's name, in their argocd.argoproj.io/tracking-id annotation, not
  // by this label. Changing it replaces the Application: the old one is pruned,
  // and its finalizer deletes everything it deployed before the new one redeploys.
  releaseName: 'frontier-' + app.name + '-dev',

  managedBy: 'argocd',

  // The tag is not set here. It is the imageTag top-level argument, the
  // frontier-dev commit sha that kubernetes/deploy/development.jsonnet passes in.
  image: {
    repository: app.imageRepository,
  },

  mysql: {
    enabled: true,
    // Collation is how MySQL sorts and compares text. The app database keeps
    // utf8mb4_0900_ai_ci. The extra database uses the other allowed collation.
    collation: 'utf8mb4_0900_ai_ci',
    databases: [
      { name: 'reporting', collation: 'utf8mb4_unicode_ci' },
    ],
    users: [
      { name: 'reader', type: 'CLOUD_IAM_USER', email: 'chaitanya.prasad@withpersona.com' },
      {
        name: 'prod-app',
        type: 'CLOUD_IAM_SERVICE_ACCOUNT',
        email: 'app-admission-canary-prod@persona-frontier-staging.iam.gserviceaccount.com',
      },
    ],
    instance: {
      // Vertical scale from db-custom-1-3840, still zonal. Disk is already
      // 100 GB and cannot shrink. The cap drops from 200 GB to the policy max.
      tier: 'db-custom-2-7680',
      availabilityType: 'ZONAL',
      diskSize: 100,
      diskAutoresizeLimit: 100,
      deletionPolicy: 'delete',
    },
  },
}
