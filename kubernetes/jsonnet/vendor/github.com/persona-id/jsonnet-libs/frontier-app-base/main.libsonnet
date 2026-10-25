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
local envoyFilter = import 'lib/envoyfilter.libsonnet';
local externalSecret = import 'lib/externalsecret.libsonnet';
local h = import 'lib/helpers.libsonnet';
local iamPolicy = import 'lib/iampolicy.libsonnet';
local job = import 'lib/job.libsonnet';
local knativeService = import 'lib/knativeservice.libsonnet';
local mongoDatabase = import 'lib/mongodatabase.libsonnet';
local mysqlDatabase = import 'lib/mysqldatabase.libsonnet';
local namespace = import 'lib/namespace.libsonnet';
local onePasswordItem = import 'lib/onepassworditem.libsonnet';
local peerAuthentication = import 'lib/peerauthentication.libsonnet';
local persistentVolumeClaim = import 'lib/persistentvolumeclaim.libsonnet';
local podDisruptionBudget = import 'lib/poddisruptionbudget.libsonnet';
local requestAuthentication = import 'lib/requestauthentication.libsonnet';
local role = import 'lib/role.libsonnet';
local roleBinding = import 'lib/rolebinding.libsonnet';
local sealedSecret = import 'lib/sealedsecret.libsonnet';
local secretStore = import 'lib/secretstore.libsonnet';
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

local previewConfig(config, prNumber) =
  local pr = std.toString(prNumber);
  assert pr != '' && pr[0] != '0' && std.all([std.member('0123456789', c) for c in std.stringChars(pr)]) :
         'prNumber must be a positive integer, got "%s"' % pr;
  local dev = std.mergePatch(defaults, config);
  assert std.endsWith(dev.namespace, '-dev') :
         'a preview is rendered from the development config, whose namespace ends in -dev; got "%s"' % dev.namespace;
  local suffix = '-pr-' + pr;
  local ns = dev.namespace + suffix;
  // Knative names the host app-<namespace>, and a DNS label is at most 63 characters.
  assert std.length('app-' + ns) <= 63 :
         "the preview hostname label app-%s is %d characters, over DNS's 63; the app name is too long for previews"
         % [ns, std.length('app-' + ns)];

  // Points URLs the app builds from its own dev hostname, such as OAuth callbacks, at the preview's.
  local devHost = 'app-%s.' % dev.namespace;
  local previewHost = 'app-%s.' % ns;
  local retarget(env) = [
    e + (if std.isString(std.get(e, 'value')) then { value: std.strReplace(e.value, devHost, previewHost) } else {})
    for e in env
  ];
  local bg = dev.backgroundJobs;
  {
    dev: dev,
    cfg: std.mergePatch(dev, {
      appName: dev.appName + suffix,
      backgroundJobs: {
        scheduled: [job { env: retarget(h.get(job, 'env', [])), suspend: true } for job in bg.scheduled],
        workers: [worker { env: retarget(h.get(worker, 'env', [])) } for worker in bg.workers],
      },
      env: retarget(dev.env) + [
        { name: 'FRONTIER_PREVIEW', value: 'true' },
        { name: 'FRONTIER_PREVIEW_PR', value: pr },
      ],
      // A GCP service account binds the dev namespace's `app` only; the preview reaches
      // the dev buckets as its own workload identity instead. MySQL is off for the
      // same reason: the dev database user is that service account, not a copied secret.
      gcpServiceAccount: { enabled: false },
      mysql: { enabled: false, migration: { enabled: false } },
      homestead: { catalog: 'dev' },
      namespace: ns,
      releaseName: h.releaseName(dev) + suffix,
    }),
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
    local delegated = h.delegatedCallers(cfg) != [];
    local forgeUsed = delegated || std.any([std.startsWith(p, 'forge/') for r in h.routes(cfg) for p in r.principals]);
    local migrate = cfg.mysql.enabled && cfg.mysql.migration.enabled;
    // The grant runs in wave 0. A migration follows in wave 1; otherwise app
    // workloads can start in wave 1 as soon as the grant has succeeded.
    local afterMysqlSetup =
      if cfg.mysql.enabled
      then { metadata+: { annotations+: { 'argocd.argoproj.io/sync-wave': if migrate then '2' else '1' } } }
      else {};

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
      [if cfg.mysql.enabled then 'mysqlDatabase']: mysqlDatabase.app(cfg),
      [if migrate then 'mysqlMigration']: job.mysqlMigration(cfg),

      namespace: namespace.app(cfg),

      // Keyed by normalized name.
      onePasswordItems: {
        [h.normalize(item.name)]: onePasswordItem.item(cfg, item)
        for item in cfg.secrets.sources.onePassword.items
      },

      // Keyed by normalized name.
      [if bg.enabled then 'scheduledJobs']: {
        [h.normalize(h.get(job, 'name', ''))]: cronJob.scheduled(cfg, job) + afterMysqlSetup
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
      service: knativeService.app(cfg) + afterMysqlSetup,
      serviceAccount: serviceAccount.app(cfg),

      // Only when a route names a Forge app, or `delegatedCallers` is set.
      [if forgeUsed then 'forgeRequestAuthentication']: requestAuthentication.forge(cfg),
      [if forgeUsed then 'forgeVirtualService']: virtualService.forge(cfg),
      [if delegated then 'forgeHeaderSanitizer']: envoyFilter.forgeHeaderSanitizer(cfg),

      [if oktaAllowlist then 'ssoRequestAuthentication']: requestAuthentication.okta(cfg),
      [if oktaRoutes then 'ssoRequireAuth']: authorizationPolicy.requireAuth(cfg),

      // Keyed by normalized name.
      [if bg.enabled then 'workers']: {
        [h.normalize(h.get(worker, 'name', ''))]: deployment.worker(cfg, worker) + afterMysqlSetup
        for worker in bg.workers
      },
    } + {
      // `valkey` and `jobQueue`, each with the objects in `valkey` above.
      [name]: valkey(cfg, instances[name])
      for name in std.objectFields(instances)
    },

  // Renders pull request `prNumber`'s preview environment from the app's merged
  // development `config`, into <dev namespace>-pr-<prNumber>, against the dev app's
  // Secrets, Mongo database and buckets, which `previewAccess` gives it; see the
  // README. MySQL stays off: its database user is the dev namespace's workload
  // identity, which a preview cannot assume. `prNumber` may be a string, as an
  // Argo CD top-level argument is.
  preview(config, prNumber)::
    local p = previewConfig(config, prNumber);

    $.new(p.cfg) + {
      domainMappings:: {},
      gcsStorageBuckets:: {},
      mongoDatabase:: {},
      mysqlDatabase:: {},
      mysqlMigration:: {},
      namespace+: { metadata+: { labels+: { 'frontier.withpersona.com/preview': 'true' } } },
      onePasswordItems:: {},
      sealedSecrets:: {},
      // The pull request comment Argo CD posts links here.
      [if p.cfg.visibility != 'none' then 'service']+: {
        metadata+: { annotations+: { 'link.argocd.argoproj.io/external-link': h.appURL(p.cfg) } },
      },
    },

  // The dev app's Secrets and bucket roles for pull request `prNumber`'s preview.
  // Rendered from the default branch, so a pull request can't change what it gets.
  previewAccess(config, prNumber)::
    local p = previewConfig(config, prNumber);
    local secrets = h.secretNames(p.cfg);

    {
      // Keyed by the bucket's `name` as configured. The buckets are the dev app's.
      gcsStorageBuckets: {
        [item.name]: { iamPolicyMember: iamPolicy.previewBucket(p.cfg, p.dev.namespace, item) }
        for item in p.cfg.gcsStorageBuckets
      },

      [if secrets != [] then 'devSecrets']: {
        externalSecrets: { [name]: externalSecret.previewDev(p.cfg, name) for name in secrets },
        role: role.previewSecretReader(p.cfg, p.dev.namespace),
        roleBinding: roleBinding.previewSecretReader(p.cfg, p.dev.namespace),
        secretStore: secretStore.previewDev(p.cfg, p.dev.namespace),
        serviceAccount: serviceAccount.previewSecretReader(p.cfg),
      },
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
