// ServiceAccounts: `app`, which every workload runs as, and one per Valkey instance.
local h = import 'helpers.libsonnet';
local serviceAccount = (import 'libs.libsonnet').k.core.v1.serviceAccount;

{
  // The identity of the web service, workers and scheduled jobs, and the only one
  // the Valkey instances' AuthorizationPolicies accept.
  app(cfg)::
    serviceAccount.new('app')
    + (
      if cfg.gcpServiceAccount.enabled then
        serviceAccount.metadata.withAnnotations({
          'iam.gke.io/gcp-service-account':
            h.get(cfg.gcpServiceAccount, 'email', '%s@persona-frontier.iam.gserviceaccount.com' % cfg.appName),
        })
      else {}
    )
    + serviceAccount.metadata.withLabels(h.labels(cfg))
    + serviceAccount.withImagePullSecrets([{ name: 'ghcr-pull-secret' }]),

  valkey(cfg, instance)::
    serviceAccount.new(instance.name)
    + serviceAccount.metadata.withLabels(h.valkeyLabels(cfg, instance))
    // Nothing in Valkey talks to the API server.
    + serviceAccount.withAutomountServiceAccountToken(false),
}
