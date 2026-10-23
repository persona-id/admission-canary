// Rejects configs that would render broken, colliding or silently open objects,
// with the same messages as the Helm chart's `fail` calls. Merged into what `new`
// returns, so the checks run whenever the result is rendered.
local h = import 'helpers.libsonnet';

// Names the library already uses for objects of its own.
local reserved = ['app', 'valkey', 'job-queue'];

// What the Frontier kro resource accepted as a username: it ends up in RoleBinding
// names and in the user's email.
local isUsername(u) =
  std.isString(u) && u != '' && std.all([std.member('abcdefghijklmnopqrstuvwxyz0123456789-.', c) for c in std.stringChars(u)]);

function(cfg)
  local auth = cfg.auth;
  local bg = cfg.backgroundJobs;
  local queue = cfg.jobQueue;
  local names = [h.normalize(h.get(w, 'name', '')) for w in bg.workers + bg.scheduled];
  local duplicates = std.set([n for n in names if std.count(names, n) > 1]);
  local restrictsIdentities = auth.allow.emails != [] || auth.allow.groups != [];
  local usesAuth = auth.required || auth.unauthedPaths != [] || auth.authedPaths != [] || restrictsIdentities;

  // Each route's problems, in the order the chart checks them.
  local checkRoute(i, r) =
    local name = 'routes[%d]' % i;
    local humans = h.get(r, 'humans', '');
    local forgeName(p) = std.substr(p, std.length('forge/'), std.length(p));
    local isForge(p) = std.startsWith(p, 'forge/') && forgeName(p) != '' && std.all([std.member('abcdefghijklmnopqrstuvwxyz0123456789-', c) for c in std.stringChars(forgeName(p))]);
    local isPrincipal(p) = isForge(p) || (std.startsWith(p, 'spiffe://') && std.length(p) > std.length('spiffe://'));
    (if h.get(r, 'paths', []) == [] then ['%s needs paths.' % name] else [])
    + (if !std.member(['none', 'anyone', 'okta'], humans) then ['%s.humans must be none, anyone or okta.' % name] else [])
    + (if (h.get(r, 'groups', []) != [] || h.get(r, 'emails', []) != []) && humans != 'okta'
       then ['%s sets groups or emails, which only apply with humans: okta.' % name] else [])
    + (if std.objectHas(r, 'apps') then ['%s.apps is now frontierApps.' % name] else [])
    + [
      '%s.principals entry "%s" must be forge/<forge-app> or start with spiffe://.' % [name, p]
      for p in h.get(r, 'principals', [])
      if !isPrincipal(p)
    ]
    + (if cfg.visibility == 'none' && humans != 'none'
       then ['%s lets humans in, but visibility: none gives them no hostname to use.' % name] else []);
  // Knative serves on one port and refuses a probe aimed at any other, so a probe
  // on the app container either leaves the port out or names `service.port`
  // itself. Failing here beats a Revision the webhook rejects.
  local probeErrors = [
    '%s.%s.port is %s; Knative only probes the serving port. Leave it out, or set it to service.port (%d).' % [key, handler, cfg[key][handler].port, cfg.service.port]
    for key in ['livenessProbe', 'readinessProbe', 'startupProbe']
    for handler in ['httpGet', 'tcpSocket']
    if std.isObject(std.get(h.get(cfg, key, {}), handler))
       && std.objectHas(cfg[key][handler], 'port')
       && (std.isString(cfg[key][handler].port) || cfg[key][handler].port != cfg.service.port)
  ];
  local routeErrors = std.flatMap(function(i) checkRoute(i, cfg.routes[i]), std.range(0, std.length(cfg.routes) - 1));

  {
    assert cfg.appName != '' : 'appName is required',
    assert cfg.namespace != '' : 'namespace is required',

    assert cfg.permissions.owner != '' : 'permissions.owner is required: a username, without @withpersona.com',
    assert isUsername(cfg.permissions.owner) :
           'permissions.owner "%s" must be a username of lowercase letters, digits, - and ., without @withpersona.com.' % cfg.permissions.owner,
    assert std.all([isUsername(u) for u in cfg.permissions.additionalCollaborators]) :
           'permissions.additionalCollaborators entry "%s" must be a username of lowercase letters, digits, - and ., without @withpersona.com.'
           % [u for u in cfg.permissions.additionalCollaborators if !isUsername(u)][0],
    assert std.member(['prod', 'dev'], cfg.homestead.catalog) :
           'homestead.catalog must be prod or dev, not "%s".' % cfg.homestead.catalog,

    assert std.member(['public', 'private', 'none'], cfg.visibility) :
           'visibility must be public, private or none, not "%s".' % cfg.visibility,
    assert !(cfg.visibility == 'none' && cfg.customDomains != []) :
           'customDomains need a gateway, and visibility: none has none.',

    assert cfg.routes == [] || !usesAuth :
           'routes replaces auth.required, auth.unauthedPaths, auth.authedPaths and auth.allow; set one or the other.',
    assert routeErrors == [] : routeErrors[0],

    // The deprecated `auth` keys, checked only when `routes` does not replace them.
    assert cfg.routes != [] || !(auth.unauthedPaths != [] && auth.authedPaths != []) :
           'auth.unauthedPaths and auth.authedPaths disagree about what an unlisted path means; set one or the other.',
    assert cfg.routes != [] || auth.required || (auth.unauthedPaths == [] && auth.authedPaths == []) :
           'auth.unauthedPaths and auth.authedPaths only scope the gate that auth.required turns on; without auth.required: true the app is open to everyone.',
    assert cfg.routes != [] || auth.required || !restrictsIdentities :
           'auth.allow.emails and auth.allow.groups restrict who gets through the gate that auth.required turns on; without auth.required: true they are ignored and the app is open to everyone.',

    assert bg.enabled || (bg.workers == [] && bg.scheduled == []) :
           'backgroundJobs.workers and backgroundJobs.scheduled are only rendered when backgroundJobs.enabled is true.',
    assert std.all([h.get(w, 'name', '') != '' for w in bg.workers + bg.scheduled]) :
           'every backgroundJobs worker and scheduled entry needs a name',
    assert std.all([!std.member(reserved, n) for n in names]) :
           'backgroundJobs name "%s" collides with a name the library already owns (%s).'
           % [[n for n in names if std.member(reserved, n)][0], std.join(', ', reserved)],
    assert duplicates == [] :
           'backgroundJobs name "%s" is used more than once; names must be unique across workers and scheduled.' % duplicates[0],
    assert std.all([!h.get(w, 'singleInstance', false) || h.get(w, 'replicas', 1) <= 1 for w in bg.workers]) :
           'a worker that sets singleInstance cannot set replicas above 1; singleInstance means exactly one copy.',

    assert probeErrors == [] : probeErrors[0],

    assert !cfg.mysql.migration.enabled || cfg.mysql.enabled :
           'mysql.migration runs against the app database, which mysql.enabled: false turns off.',
    assert !cfg.mysql.migration.enabled || cfg.mysql.migration.command != [] :
           'mysql.migration.enabled needs mysql.migration.command.',
    assert !cfg.mysql.enabled || cfg.mysql.projectId != '' :
           'mysql.projectId is required when mysql.enabled is true.',
    assert std.member(['environment-default', 'zonal', 'regional-ha'], cfg.mysql.instance.profile) :
           'mysql.instance.profile must be environment-default, zonal or regional-ha, not "%s".' % cfg.mysql.instance.profile,
    assert !(cfg.mysql.enabled && cfg.gcpServiceAccount.enabled) :
           'mysql.enabled cannot be combined with gcpServiceAccount.enabled; MySQL provisions its own workload identity.',
    assert !cfg.mysql.enabled || (std.startsWith(cfg.namespace, 'frontier-') && std.length(cfg.namespace) <= 35) :
           'mysql.enabled requires a frontier-* namespace of at most 35 characters so the generated service account id fits.',
    assert !cfg.mysql.enabled || cfg.mysql.region != '' :
           'mysql.region is required when mysql.enabled is true.',

    assert !queue.enabled || h.get(queue, 'client', '') == '' || std.objectHas(h.queueClientVars, queue.client) :
           'jobQueue.client "%s" is not one of sidekiq, bullmq and asynq.' % queue.client,
  }
