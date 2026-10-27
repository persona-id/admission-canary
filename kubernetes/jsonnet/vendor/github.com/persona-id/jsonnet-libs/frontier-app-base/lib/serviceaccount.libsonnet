// ServiceAccounts: `app`, which every workload runs as, one per Valkey instance, and a
// preview's secret reader.
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

  // The Cloud SQL proxy's identity. Workload Identity is the pod's ServiceAccount,
  // so this has to be a different pod from the app or the app would hold the same
  // Google service account.
  mysqlProxy(cfg)::
    serviceAccount.new(h.mysqlProxyService)
    + serviceAccount.metadata.withAnnotations({
      'iam.gke.io/gcp-service-account': '%s@%s.iam.gserviceaccount.com' % [h.mysqlAccountId(cfg), h.mysqlProjectId(cfg)],
    })
    + serviceAccount.metadata.withLabels(h.labels(cfg)),

  previewSecretReader(cfg)::
    serviceAccount.new(h.previewSecretReader)
    + serviceAccount.metadata.withLabels(h.labels(cfg)),

  valkey(cfg, instance)::
    serviceAccount.new(instance.name)
    + serviceAccount.metadata.withLabels(h.valkeyLabels(cfg, instance))
    // Nothing in Valkey talks to the API server.
    + serviceAccount.withAutomountServiceAccountToken(false),
}
