// The app's Namespace, with the labels the Frontier kro ResourceGraphDefinition in
// persona-kubernetes used to give it.
local h = import 'helpers.libsonnet';
local namespace = (import 'libs.libsonnet').k.core.v1.namespace;

{
  app(cfg)::
    namespace.new(cfg.namespace)
    + namespace.metadata.withLabels(h.labels(cfg) {
      app: cfg.appName,
      environment: cfg.clusterEnvironment,
      'homestead.withpersona.com/catalog': cfg.homestead.catalog,
      // Sidecar injection from the stable Istio control plane. Without it the
      // app's pods join no mesh, and none of its Istio policies apply.
      'istio.io/rev': 'stable',
      name: cfg.namespace,
    } + (
      // The cluster's Frontier MySQL admission policy reads this label to scope
      // its Cloud SQL / Workload Identity shape checks to opted-in apps only.
      if cfg.mysql.enabled then { 'frontier.withpersona.com/mysql-database': 'true' } else {}
    )),
}
