// frontier-app-base: everything a Frontier app deploys — its namespace and who may
// manage it, the Knative service, background workers and scheduled jobs, Valkey,
// secrets, SSO, buckets and Mongo — from a single config object. The jsonnet port of the Helm chart of the same name
// in persona-frontier-base; see config.libsonnet for every option.
//
//   local frontier = import 'github.com/persona-id/jsonnet-libs/frontier-app-base/main.libsonnet';
//
//   frontier.new({
//     appName: 'my-app',
//     namespace: 'frontier-my-app-prod',
//     permissions: { owner: 'jane.doe' },
//     image: { repository: 'ghcr.io/persona-id/my-app', tag: 'abc123' },
//   })
//
// lib/ has one file per Kubernetes kind, each exporting constructors for the
// objects of that kind; this file assembles them into what `new` returns.
local defaults = import 'config.libsonnet';
local authorizationPolicy = import 'lib/authorizationpolicy.libsonnet';
local configMap = import 'lib/configmap.libsonnet';
local cronJob = import 'lib/cronjob.libsonnet';
local deployment = import 'lib/deployment.libsonnet';
local domainMapping = import 'lib/domainmapping.libsonnet';
local h = import 'lib/helpers.libsonnet';
local iamPolicy = import 'lib/iampolicy.libsonnet';
local knativeService = import 'lib/knativeservice.libsonnet';
local mongoDatabase = import 'lib/mongodatabase.libsonnet';
local namespace = import 'lib/namespace.libsonnet';
local onePasswordItem = import 'lib/onepassworditem.libsonnet';
local peerAuthentication = import 'lib/peerauthentication.libsonnet';
local persistentVolumeClaim = import 'lib/persistentvolumeclaim.libsonnet';
local podDisruptionBudget = import 'lib/poddisruptionbudget.libsonnet';
local requestAuthentication = import 'lib/requestauthentication.libsonnet';
local roleBinding = import 'lib/rolebinding.libsonnet';
local sealedSecret = import 'lib/sealedsecret.libsonnet';
local service = import 'lib/service.libsonnet';
local serviceAccount = import 'lib/serviceaccount.libsonnet';
local storageBucket = import 'lib/storagebucket.libsonnet';
local validation = import 'lib/validation.libsonnet';
local virtualService = import 'lib/virtualservice.libsonnet';

// Everything one Valkey instance needs.
local valkey(cfg, instance) = {
  authorizationPolicy: authorizationPolicy.valkey(cfg, instance),
  configMap: configMap.valkey(cfg, instance),
  deployment: deployment.valkey(cfg, instance),
  peerAuthentication: peerAuthentication.valkey(cfg, instance),
  [if instance.storage != null then 'persistentVolumeClaim']: persistentVolumeClaim.valkey(cfg, instance),
  service: service.valkey(cfg, instance),
  serviceAccount: serviceAccount.valkey(cfg, instance),
};

{
  defaults:: defaults,

  // Renders the app. `config` is deep-merged over `defaults` like Helm values:
  // objects merge key by key, lists and scalars replace.
  //
  // The result is an object of Kubernetes objects, nested by component, which Tanka
  // renders as-is. Any object can be patched with `+`, e.g.
  //   frontier.new(config) + { service+: { metadata+: { annotations+: { a: 'b' } } } }
  new(config)::
    local cfg = std.mergePatch(defaults, config);
    local bg = cfg.backgroundJobs;
    local oktaRoutes = std.any([r.humans == 'okta' for r in h.routes(cfg)]);
    local oktaAllowlist = h.oktaAllowlist(cfg);
    local instances = h.valkeyInstances(cfg);
    local forgeUsed = std.any([std.startsWith(p, 'forge/') for r in h.routes(cfg) for p in r.principals]);

    validation(cfg) + {
      _config:: cfg,

      // Default-deny for the app: who may reach which paths, per `routes`.
      allowIntraNamespace: authorizationPolicy.intraNamespace(cfg),
      authorizationPolicy: authorizationPolicy.app(cfg),

      // Keyed by fqdn.
      domainMappings: {
        [item.fqdn]: domainMapping.customDomain(cfg, item)
        for item in cfg.customDomains
      },

      // Keyed by the bucket's `name` as configured.
      gcsStorageBuckets: {
        [item.name]: {
          bucket: storageBucket.bucket(cfg, item),
          iamPolicy: iamPolicy.bucket(cfg, item),
        }
        for item in cfg.gcsStorageBuckets
      },

      [if cfg.mongo.enabled then 'mongoDatabase']: mongoDatabase.app(cfg),

      namespace: namespace.app(cfg),

      // Keyed by normalized name.
      onePasswordItems: {
        [h.normalize(item.name)]: onePasswordItem.item(cfg, item)
        for item in cfg.secrets.sources.onePassword.items
      },

      // Keyed by normalized name.
      [if bg.enabled then 'scheduledJobs']: {
        [h.normalize(h.get(job, 'name', ''))]: cronJob.scheduled(cfg, job)
        for job in bg.scheduled
      },

      // Keyed by normalized name.
      sealedSecrets: {
        [h.normalize(item.name)]: sealedSecret.item(cfg, item)
        for item in cfg.secrets.sources.sealedSecrets.items
      },

      // Who may manage the namespace, keyed by RoleBinding name.
      roleBindings: {
        'owner-crd-access': roleBinding.ownerCrdAccess(cfg),
        'owner-edit': roleBinding.ownerEdit(cfg),
      } + {
        ['collaborator-crd-access-' + user]: roleBinding.collaboratorCrdAccess(cfg, user)
        for user in std.set(cfg.permissions.additionalCollaborators)
      } + {
        ['collaborator-edit-' + user]: roleBinding.collaboratorEdit(cfg, user)
        for user in std.set(cfg.permissions.additionalCollaborators)
      },

      // Only when enabled and at least two pods are kept running: with one,
      // maxUnavailable 1 protects nothing, and anything stricter would stop a
      // node drain for good.
      [if h.get(h.get(cfg, 'podDisruptionBudget', {}), 'enabled', false) && cfg.scaling.minScale >= 2 then 'podDisruptionBudget']:
        podDisruptionBudget.app(cfg),

      // STRICT mTLS, without which the app's AuthorizationPolicy cannot identify
      // Knative's own callers.
      peerAuthentication: peerAuthentication.app(cfg),

      // The web service.
      service: knativeService.app(cfg),
      serviceAccount: serviceAccount.app(cfg),

      // Only when a route names a Forge app.
      [if forgeUsed then 'forgeRequestAuthentication']: requestAuthentication.forge(cfg),
      [if forgeUsed then 'forgeVirtualService']: virtualService.forge(cfg),

      [if oktaAllowlist then 'ssoRequestAuthentication']: requestAuthentication.okta(cfg),
      [if oktaRoutes then 'ssoRequireAuth']: authorizationPolicy.requireAuth(cfg),

      // Keyed by normalized name.
      [if bg.enabled then 'workers']: {
        [h.normalize(h.get(worker, 'name', ''))]: deployment.worker(cfg, worker)
        for worker in bg.workers
      },
    } + {
      // `valkey` and `jobQueue`, each with the objects in `valkey` above.
      [name]: valkey(cfg, instances[name])
      for name in std.objectFields(instances)
    },

  // Flattens what `new` returns into a plain list of Kubernetes objects, for
  // `jsonnet` + `kubectl apply` outside of Tanka.
  toList(rendered)::
    local walk(o) =
      if std.isObject(o) then
        if std.objectHas(o, 'apiVersion') && std.objectHas(o, 'kind') then [o]
        else std.flatMap(function(key) walk(o[key]), std.objectFields(o))
      else if std.isArray(o) then std.flatMap(walk, o)
      else [];
    walk(rendered),
}
