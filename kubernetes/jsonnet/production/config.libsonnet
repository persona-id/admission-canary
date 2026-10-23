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
}
