// Building blocks shared across resource kinds. Each takes the merged config `cfg`.
local k = (import 'libs.libsonnet').k;

local container = k.core.v1.container;
local envVar = k.core.v1.envVar;
local projection = k.core.v1.volumeProjection;
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;

local computeClassKey = 'cloud.google.com/compute-class';

// The variable each named job-queue client reads, on top of JOB_QUEUE_URL.
local queueClientVars = {
  // asynq wants host:port rather than a URL.
  asynq: { name: 'REDIS_ADDR', value: 'job-queue:6379' },
  bullmq: { name: 'REDIS_URL', value: 'redis://job-queue:6379' },
  sidekiq: { name: 'REDIS_URL', value: 'redis://job-queue:6379' },
};

// The workload sizes for `backgroundJobs`. No tier sets a CPU limit: throttling a
// worker turns a slow queue into a stuck one.
local sizes = {
  large: { limits: { memory: '8Gi' }, requests: { cpu: '1', memory: '4Gi' } },
  medium: { limits: { memory: '2Gi' }, requests: { cpu: '500m', memory: '1Gi' } },
  small: { limits: { memory: '512Mi' }, requests: { cpu: '100m', memory: '256Mi' } },
};

{
  appImage(cfg):: '%s:%s' % [cfg.image.repository, cfg.image.tag],

  // The identity the backing services' AuthorizationPolicies accept, and the one
  // every workload runs as.
  appPrincipal(cfg):: 'cluster.local/ns/%s/sa/app' % cfg.namespace,

  // Cloud IAM service account IDs are limited to 30 characters. Keep both ends
  // when truncating so environment/user suffixes remain distinct. Enabled MySQL
  // namespaces are at most 35 characters, so the untruncated form is the one
  // the staging admission policy allows.
  mysqlAccountId(cfg)::
    local namespacePrefix = 'frontier-';
    local accountPrefix = 'app-';
    local app = if std.startsWith(cfg.namespace, namespacePrefix) then std.substr(cfg.namespace, std.length(namespacePrefix), std.length(cfg.namespace)) else cfg.namespace;
    if std.length(app) <= 26 then accountPrefix + app
    else '%s%s-%s' % [accountPrefix, std.substr(app, 0, 17), std.substr(app, std.length(app) - 8, 8)],

  mysqlProxyContainer(cfg, nativeSidecar=false)::
    {
      name: 'cloud-sql-proxy',
      image: cfg.mysql.proxy.image,
      args: [
        '--auto-iam-authn',
        '--health-check',
        '--http-address=0.0.0.0',
        '--http-port=9091',
        '--private-ip',
        '--structured-logs',
        '--port=%d' % cfg.mysql.proxy.port,
        '$(INSTANCE_CONNECTION_NAME)',
      ],
      env: [{
        name: 'INSTANCE_CONNECTION_NAME',
        valueFrom: {
          configMapKeyRef: {
            key: 'instanceConnectionName',
            name: 'mysql-connection',
          },
        },
      }],
      resources: {
        limits: { cpu: '160m', memory: '64Mi' },
        requests: { cpu: '100m', memory: '32Mi' },
      },
      securityContext: {
        allowPrivilegeEscalation: false,
        runAsNonRoot: true,
      },
    }
    // Knative rejects probes on a sidecar unless multi-container probing is on.
    // A native sidecar's startup probe holds the main container until the proxy is up.
    + (if nativeSidecar then {
         livenessProbe: {
           httpGet: { path: '/liveness', port: 9091 },
           periodSeconds: 10,
           timeoutSeconds: 5,
         },
         restartPolicy: 'Always',
         startupProbe: {
           failureThreshold: 30,
           httpGet: { path: '/startup', port: 9091 },
           periodSeconds: 1,
           timeoutSeconds: 5,
         },
       } else {}),

  // A `gcsStorageBuckets` entry's role for the app.
  bucketAppRole(item):: $.get(item, 'appPermissions', 'roles/storage.objectUser'),

  // A `gcsStorageBuckets` entry's bucket name, shared by its StorageBucket and IAMPartialPolicy.
  bucketName(item):: 'persona-frontier-%s' % $.normalize(item.name),

  // Every env var a workload gets, in precedence order — later entries win.
  envEntries(cfg, extra=[])::
    [
      envVar.fromSecretRef(e.name, $.normalize(e.fromSecretName), $.get(e, 'secretKey', 'value'))
      for e in $.resolvedSecrets(cfg).envVars
    ]
    + (if cfg.valkey.enabled then [
         envVar.new('REDIS_URL', 'redis://valkey:6379'),
         envVar.new('VALKEY_URL', 'redis://valkey:6379'),
       ] else [])
    + (if cfg.jobQueue.enabled then
         [envVar.new('JOB_QUEUE_URL', 'redis://job-queue:6379')]
         + (
           local client = $.get(cfg.jobQueue, 'client', '');
           if client == '' then [] else [envVar.new(queueClientVars[client].name, queueClientVars[client].value)]
         )
       else [])
    + (if cfg.mongo.enabled then [
         envVar.fromSecretRef('MONGODB_URI', 'mongo-credentials', 'connectionStringPrivateSrv'),
         envVar.fromSecretRef('MONGODB_DB_NAME', 'mongo-credentials', 'username'),
       ] else [])
    + (if cfg.mysql.enabled then [
         {
           name: 'MYSQL_DATABASE',
           valueFrom: { configMapKeyRef: { key: 'database', name: 'mysql-connection' } },
         },
         envVar.new('MYSQL_HOST', '127.0.0.1'),
         envVar.new('MYSQL_PORT', std.toString(cfg.mysql.proxy.port)),
         {
           name: 'MYSQL_USER',
           valueFrom: { configMapKeyRef: { key: 'user', name: 'mysql-connection' } },
         },
       ] else [])
    + (if $.get(cfg.source, 'revision', '') != '' then [envVar.new('DD_GIT_COMMIT_SHA', std.toString(cfg.source.revision))] else [])
    + (if $.get(cfg.source, 'repository', '') != '' then [envVar.new('DD_GIT_REPOSITORY_URL', std.toString(cfg.source.repository))] else [])
    + [envVar.new(e.name, std.toString(e.value)) for e in cfg.env + extra],

  // Datadog's agent maps this pod label to the env tag, overriding the
  // cluster-wide DD_ENV that can't be right for both dev and prod.
  environment(cfg):: if $.isProduction(cfg) then 'production' else 'development',

  // `o[key]`, or `default` when it is missing, null or ''. Unlike Helm's `default`,
  // an explicit 0 or false is kept.
  get(o, key, default):: local v = std.get(o, key, null); if v == null || v == '' then default else v,

  // The names that address the app from inside the cluster.
  inClusterHosts(cfg):: ['app.%s' % cfg.namespace, 'app.%s.svc' % cfg.namespace, 'app.%s.svc.cluster.local' % cfg.namespace],

  isProduction(cfg):: std.endsWith(cfg.namespace, '-prod'),

  // Common labels for everything the library renders.
  labels(cfg):: {
    'app.kubernetes.io/instance': $.releaseName(cfg),
    'app.kubernetes.io/managed-by': cfg.managedBy,
    'app.kubernetes.io/name': 'frontier-app-base',
  },

  // Normalize a name for use with Kubernetes resources.
  normalize(name):: std.strReplace(std.strReplace(std.asciiLower(name), ' ', '-'), '_', '-'),

  // Pod placement for a compute class: the node selector plus its taint's
  // toleration, followed by `cfg.tolerations`. `computeClass` '' means neither.
  placement(cfg, computeClass):: {
    nodeSelector: if computeClass != '' then { [computeClassKey]: computeClass } else {},
    tolerations:
      (if computeClass != '' then [
         k.core.v1.toleration.withEffect('NoSchedule')
         + k.core.v1.toleration.withKey(computeClassKey)
         + k.core.v1.toleration.withOperator('Equal')
         + k.core.v1.toleration.withValue(computeClass),
       ] else [])
      + cfg.tolerations,
  },

  // The env and mounts every workload's container shares, omitting empty lists.
  podContainerMixin(cfg, extraEnv=[])::
    local env = $.podEnv(cfg, extraEnv);
    local mounts = $.podVolumeMounts(cfg);
    (if env != [] then container.withEnv(env) else {})
    + (if mounts != [] then container.withVolumeMounts(mounts) else {}),

  // The env block, shared by every workload. A repeated name keeps its first
  // position and takes its last value, so the list never repeats a name — Knative
  // rejects a container that does.
  podEnv(cfg, extra=[])::
    local entries = $.envEntries(cfg, extra);
    local winners = std.foldl(function(acc, e) acc { [e.name]: e }, entries, {});
    local names = std.foldl(function(acc, e) if std.member(acc, e.name) then acc else acc + [e.name], entries, []);
    [winners[name] for name in names],

  // Volume mounts shared by every workload: secret mounts plus projected SA tokens.
  podVolumeMounts(cfg)::
    [
      volumeMount.new($.normalize(m.fromSecretName), m.path, readOnly=true)
      for m in $.resolvedSecrets(cfg).mounts
    ]
    + [
      volumeMount.new($.normalize(t.name), t.mountPath, readOnly=true)
      for t in cfg.serviceAccountTokens
    ],

  // Volumes backing the mounts above.
  podVolumes(cfg)::
    [
      volume.fromSecret($.normalize(m.fromSecretName), $.normalize(m.fromSecretName))
      for m in $.resolvedSecrets(cfg).mounts
    ]
    + [
      assert $.get(t, 'audience', '') != '' : 'serviceAccountTokens[].audience is required';
      volume.projected.withSources([
        projection.serviceAccountToken.withAudience(t.audience)
        + projection.serviceAccountToken.withExpirationSeconds($.get(t, 'expirationSeconds', 3600))
        + projection.serviceAccountToken.withPath($.get(t, 'fileName', 'token')),
      ])
      + volume.withName($.normalize(t.name))
      for t in cfg.serviceAccountTokens
    ],

  queueClientVars:: queueClientVars,

  releaseName(cfg):: $.get(cfg, 'releaseName', cfg.appName),

  // Folds sealedSecrets items into the plain envVars/mounts lists.
  resolvedSecrets(cfg)::
    local sealed = cfg.secrets.sources.sealedSecrets.items;
    {
      envVars: cfg.secrets.envVars + [
        { fromSecretName: item.name, name: item.envVar }
        for item in sealed
        if $.get(item, 'envVar', '') != ''
      ],
      mounts: cfg.secrets.mounts + [
        { fromSecretName: item.name, path: item.mountPath }
        for item in sealed
        if $.get(item, 'mountPath', '') != ''
      ],
    },

  // The app's routes in priority order, each with its fields filled in: `routes`
  // as written, or what the older `auth` keys mean in routes. `/metrics` and
  // `/healthz` go first, open to anyone who can reach the app, as they always
  // have been.
  //
  // Each route also carries `operation`, its Istio operation: its paths, minus
  // every path an earlier route claimed, which is what makes the first matching
  // route win.
  routes(cfg)::
    local auth = cfg.auth;
    local okta = { humans: 'okta', emails: auth.allow.emails, groups: auth.allow.groups };
    local legacy =
      if !auth.required then [{ paths: ['/*'], humans: 'anyone' }]
      else if auth.authedPaths != [] then [{ paths: auth.authedPaths } + okta, { paths: ['/*'], humans: 'anyone' }]
      else (if auth.unauthedPaths != [] then [{ paths: auth.unauthedPaths, humans: 'anyone' }] else [])
           + [{ paths: ['/*'] } + okta];
    local routes =
      (if cfg.visibility != 'none' then [{ paths: ['/metrics', '/healthz'], humans: 'anyone' }] else [])
      + (if cfg.routes != [] then cfg.routes else legacy);
    local filled = [
      {
        paths: $.get(r, 'paths', []),
        humans: $.get(r, 'humans', ''),
        emails: $.get(r, 'emails', []),
        groups: $.get(r, 'groups', []),
        frontierApps: $.get(r, 'frontierApps', []),
        principals: $.get(r, 'principals', []),
      }
      for r in routes
    ];
    [
      local above = std.flatMap(function(r) r.paths, filled[:i]);
      filled[i] {
        operation: { paths: filled[i].paths } + (if above != [] then { notPaths: above } else {}),
      }
      for i in std.range(0, std.length(filled) - 1)
    ],

  // Whether a route limits Okta users to emails or groups, which needs the ID
  // token verified.
  oktaAllowlist(cfg)::
    std.any([r.humans == 'okta' && (r.emails != [] || r.groups != []) for r in $.routes(cfg)]),

  sizes:: sizes,

  // `annotations` plus the deploy source's, which win a clash. The OCI keys are
  // shared with image provenance; OCI has no key for dirty state. An explicit
  // `dirty: false` is kept.
  sourceAnnotations(cfg, annotations={})::
    local dirty = std.get(cfg.source, 'dirty', null);
    annotations
    + (if $.get(cfg.source, 'repository', '') != '' then { 'org.opencontainers.image.source': std.toString(cfg.source.repository) } else {})
    + (if $.get(cfg.source, 'revision', '') != '' then { 'org.opencontainers.image.revision': std.toString(cfg.source.revision) } else {})
    + (if dirty != null && dirty != '' then { 'frontier.withpersona.com/source-dirty': std.toString(dirty) } else {}),

  // The two Valkey instances: `valkey`, a cache, and `job-queue`, a durable home for
  // background jobs. They want opposite behaviour when memory fills — a cache drops
  // the least recently used keys, a queue must never drop a job — so they are two
  // instances of the same shape with different configs. Keyed by the output field
  // each renders under; only enabled instances are present.
  //
  // Each is { computeClass, conf, image, name, priorityClassName, resources,
  // storage, strategy }, where `storage` is { claimName, size, storageClass }, or
  // null for an emptyDir.
  valkeyInstances(cfg)::
    local baseConfig = |||
      port %d
      # No password. Protection is STRICT mTLS plus an AuthorizationPolicy
      # admitting only the `app` ServiceAccount.
      protected-mode no
      bind * -::*
      dir /data
    ||| % $.valkeyPort;
    local cache = cfg.valkey;
    local queue = cfg.jobQueue;
    local queueClass = $.get(queue, 'computeClass', '');
    {
      // The job queue. Its address is redis://job-queue:6379.
      [if queue.enabled then 'jobQueue']: {
        computeClass: queueClass,
        conf: baseConfig + |||
          # Every job reaches disk as it arrives. This is the whole reason the queue
          # is a separate instance from the `valkey` cache.
          appendonly yes
          appendfsync everysec
          maxmemory %s
          # Refuse new work rather than deleting queued work when memory fills. The
          # cache does the opposite (allkeys-lru); one instance cannot do both.
          maxmemory-policy noeviction
        ||| % queue.maxMemory,
        image: queue.image,
        name: 'job-queue',
        priorityClassName: $.get(queue, 'priorityClassName', ''),
        resources: queue.resources,
        // A compute class's nodes only attach Hyperdisk. A claim's storage class
        // can't change, so the Hyperdisk claim gets its own name, as in the chart.
        storage: {
          claimName: if queueClass != '' then 'job-queue-hyperdisk' else 'job-queue',
          size: queue.diskSize,
          storageClass: $.get(queue, 'storageClass', if queueClass != '' then 'hyperdisk-balanced-rwo' else ''),
        },
        // The disk is ReadWriteOnce, so two pods cannot attach it at once. A rolling
        // update would wait forever for a second pod that can never start.
        strategy: 'Recreate',
      },

      // The cache. Its address is redis://valkey:6379.
      [if cache.enabled then 'valkey']: {
        computeClass: '',
        conf: baseConfig + cache.valkeyConfig,
        image: cache.image,
        name: 'valkey',
        priorityClassName: '',
        resources: cache.resources,
        storage:
          if cache.dataStorage.enabled
          then { claimName: 'valkey', size: cache.dataStorage.requestedSize, storageClass: cache.dataStorage.storageClass }
          else null,
        strategy: cache.deploymentStrategy,
      },
    },

  valkeyLabels(cfg, instance):: $.labels(cfg) { 'app.kubernetes.io/name': instance.name },

  valkeyPort:: 6379,

  valkeySelector(cfg, instance):: {
    'app.kubernetes.io/instance': $.releaseName(cfg),
    'app.kubernetes.io/name': instance.name,
  },

  // The container for a worker or scheduled job. An `image` override must already
  // be built; the app's pipeline makes one image.
  workloadContainer(cfg, name, workload)::
    local resources = $.workloadResources(cfg, workload);
    container.new(name, $.get(workload, 'image', $.appImage(cfg)))
    + $.podContainerMixin(cfg, $.get(workload, 'env', []))
    + (if std.objectHas(resources, 'limits') then container.resources.withLimits(resources.limits) else {})
    + (if std.objectHas(resources, 'requests') then container.resources.withRequests(resources.requests) else {})
    + (if $.get(workload, 'args', []) != [] then container.withArgs(workload.args) else {})
    + (if $.get(workload, 'command', []) != [] then container.withCommand(workload.command) else {}),

  // Pod labels for a worker or scheduled job: the workload's own, with the
  // library's merged over them so a clash cannot break the Deployment's selector
  // or the `environment` tag.
  workloadLabels(cfg, workload, component, name)::
    $.get(workload, 'labels', {})
    + $.labels(cfg)
    + {
      'app.kubernetes.io/component': component,
      environment: $.environment(cfg),
      'frontier.withpersona.com/workload': name,
    },

  // A worker's or scheduled job's own `computeClass` wins over the app's.
  workloadPlacement(cfg, workload):: $.placement(cfg, std.get(workload, 'computeClass', cfg.computeClass)),

  // Resources for a worker or scheduled job. `size` picks a tier and `resources`
  // merges over it.
  workloadResources(cfg, workload)::
    local size = $.get(workload, 'size', $.get(cfg.backgroundJobs, 'defaultSize', 'small'));
    assert std.objectHas(sizes, size) :
           'backgroundJobs workload "%s" sets size "%s"; valid sizes are small, medium and large.' % [workload.name, size];
    std.mergePatch(sizes[size], $.get(workload, 'resources', {})),
}
