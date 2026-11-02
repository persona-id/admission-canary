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
  local mysqlInstance = h.mysqlInstanceSettings(cfg);
  local identOk(name) =
    std.isString(name) && std.length(name) > 0 && std.length(name) <= 63 &&
    std.member('abcdefghijklmnopqrstuvwxyz', std.substr(name, 0, 1)) &&
    std.all([std.member('abcdefghijklmnopqrstuvwxyz0123456789-', c) for c in std.stringChars(name)]);
  local reservedDbs = ['mysql', 'information_schema', 'performance_schema', 'sys'];
  local mysqlDbs = if std.isArray(cfg.mysql.databases) then cfg.mysql.databases else [];
  local mysqlDbNames = [h.get(db, 'name', '') for db in mysqlDbs];
  // A MySQL database name: identOk's characters plus underscore.
  local dbNameOk(name) =
    std.isString(name) && std.length(name) > 0 && std.length(name) <= 63 &&
    std.member('abcdefghijklmnopqrstuvwxyz', std.substr(name, 0, 1)) &&
    std.member('abcdefghijklmnopqrstuvwxyz0123456789', std.substr(name, std.length(name) - 1, 1)) &&
    std.all([std.member('abcdefghijklmnopqrstuvwxyz0123456789-_', c) for c in std.stringChars(name)]);
  local appDb = h.mysqlAppDatabase(cfg);
  local mysqlDbObjectNames = [h.mysqlDatabaseObjectName(n) for n in [appDb] + mysqlDbNames if std.isString(n)];
  local mysqlDbErrors =
    (if std.isArray(cfg.mysql.databases) then [] else ['mysql.databases must be a list.'])
    + (if cfg.mysql.enabled && (!dbNameOk(appDb) || std.member(reservedDbs, appDb)) then
         ['mysql.databaseName "%s" must be a lowercase name of letters, digits, dashes and underscores, and not a MySQL system database.' % appDb]
       else [])
    + std.flatMap(function(db)
      local name = h.get(db, 'name', '');
      local collation = h.get(db, 'collation', cfg.mysql.collation);
      (if !dbNameOk(name) || std.member(reservedDbs, name) || name == appDb then
         ['mysql.databases name "%s" must be a lowercase name, not the app database, and not a MySQL system database.' % name]
       else [])
      + (if !std.member(['utf8mb4_0900_ai_ci', 'utf8mb4_unicode_ci'], collation) then
           ['mysql.databases collation for "%s" must be utf8mb4_0900_ai_ci or utf8mb4_unicode_ci.' % name]
         else [])
                  , mysqlDbs)
    + (if std.length(std.set(mysqlDbObjectNames)) != std.length(mysqlDbObjectNames) then
         ['mysql.databases names must be unique, counting "_" and "-" as the same.']
       else []);
  local mysqlUsers = if std.isArray(cfg.mysql.users) then cfg.mysql.users else [];
  local mysqlAccount = h.mysqlAccountId(cfg);
  local emailOk(email) =
    std.isString(email) && std.length(std.findSubstr('@', email)) == 1 &&
    std.all([!std.member("'\"` ", c) for c in std.stringChars(email)]);
  local mysqlUserNames = [h.get(user, 'name', '') for user in mysqlUsers];
  local mysqlUserErrors =
    (if std.isArray(cfg.mysql.users) then [] else ['mysql.users must be a list.'])
    + std.flatMap(function(user)
      local name = h.get(user, 'name', '');
      local type = h.get(user, 'type', '');
      local email = h.get(user, 'email', '');
      (if !identOk(name) || name == mysqlAccount || name == mysqlAccount + '-mysql-provisioner' then
         ['mysql.users name "%s" must be a lowercase name and must not be the app user or the provisioner.' % name]
       else [])
      + (if !std.member(['CLOUD_IAM_USER', 'CLOUD_IAM_SERVICE_ACCOUNT', 'CLOUD_IAM_GROUP'], type) then
           ['mysql.users type for "%s" must be CLOUD_IAM_USER, CLOUD_IAM_SERVICE_ACCOUNT or CLOUD_IAM_GROUP.' % name]
         else [])
      + (if !emailOk(email) ||
            (type == 'CLOUD_IAM_SERVICE_ACCOUNT' && !std.endsWith(email, '@' + h.mysqlProjectId(cfg) + '.iam.gserviceaccount.com')) ||
            (type != 'CLOUD_IAM_SERVICE_ACCOUNT' && !std.endsWith(email, '@withpersona.com')) then
           ['mysql.users email for "%s" must be @withpersona.com, or a service account in %s.' % [name, h.mysqlProjectId(cfg)]]
         else [])
      + (
        local privileges = h.mysqlUserPrivileges(user);
        if !std.isArray(privileges) || privileges == [] ||
           !std.all([std.member(h.mysqlUserPrivilegeNames, p) for p in privileges]) ||
           (std.member(privileges, 'ALL PRIVILEGES') && std.length(privileges) > 1) then
          ['mysql.users privileges for "%s" must be ["ALL PRIVILEGES"] or a list of %s.'
           % [name, std.join(', ', [p for p in h.mysqlUserPrivilegeNames if p != 'ALL PRIVILEGES'])]]
        else []
      )
      + (
        local databases = h.mysqlUserDatabases(cfg, user);
        if !std.isArray(databases) || databases == [] ||
           !std.all([std.member(h.mysqlDatabaseNames(cfg), db) for db in databases]) then
          ['mysql.users databases for "%s" must list databases on this instance: %s.' % [name, std.join(', ', h.mysqlDatabaseNames(cfg))]]
        else []
      )
                  , mysqlUsers)
    + (if std.length(std.set(mysqlUserNames)) != std.length(mysqlUserNames) then ['mysql.users names must be unique.'] else []);
  local mysqlConnections = h.mysqlConnections(cfg);
  local mysqlConnectionNames = [h.get(c, 'name', '') for c in mysqlConnections];
  local grantErrors(kind, entry) =
    local name = h.get(entry, 'name', '');
    local privileges = h.mysqlUserPrivileges(entry);
    local databases = h.mysqlUserDatabases(cfg, entry);
    (if !std.isArray(privileges) || privileges == [] ||
        !std.all([std.member(h.mysqlUserPrivilegeNames, p) for p in privileges]) ||
        (std.member(privileges, 'ALL PRIVILEGES') && std.length(privileges) > 1) then
       ['%s privileges for "%s" must be ["ALL PRIVILEGES"] or a list of %s.'
        % [kind, name, std.join(', ', [p for p in h.mysqlUserPrivilegeNames if p != 'ALL PRIVILEGES'])]]
     else [])
    + (if !std.isArray(databases) || databases == [] ||
          !std.all([std.member(h.mysqlDatabaseNames(cfg), db) for db in databases]) then
         ['%s databases for "%s" must list databases on this instance: %s.' % [kind, name, std.join(', ', h.mysqlDatabaseNames(cfg))]]
       else []);
  local mysqlConnectionErrors =
    (if std.isArray(cfg.mysql.connections) then [] else ['mysql.connections must be a list.'])
    + std.flatMap(function(c)
      local name = h.get(c, 'name', '');
      (if !std.isString(name) || name == '' || !std.all([std.member('abcdefghijklmnopqrstuvwxyz0123456789', ch) for ch in std.stringChars(name)]) ||
          std.member(['dev', 'prod'], name) then
         ['mysql.connections name "%s" must be lowercase letters and digits, and not dev or prod.' % name]
       else if std.length(h.mysqlAccountIdFor(cfg, c)) > 30 then
         ['mysql.connections name "%s" is too long: %s must fit 30 characters.' % [name, h.mysqlAccountIdFor(cfg, c)]]
       else [])
      + grantErrors('mysql.connections', c)
                  , mysqlConnections)
    + (if std.length(std.set(mysqlConnectionNames)) != std.length(mysqlConnectionNames) then ['mysql.connections names must be unique.'] else [])
    + [
      'mysql.users name "%s" is the name of a mysql.connections identity.' % u
      for u in std.setInter(std.set(mysqlUserNames), std.set([h.mysqlAccountIdFor(cfg, c) for c in mysqlConnections if std.isString(h.get(c, 'name', ''))]))
    ];
  // Flag name => whether a value is allowed. These are the flags stack-core's
  // Cloud SQL databases set; Cloud SQL checks the exact ranges.
  local digits(v) = std.length(v) > 0 && std.all([std.member('0123456789', ch) for ch in std.stringChars(v)]);
  local number(v) = std.length(v) > 0 && std.all([std.member('0123456789.', ch) for ch in std.stringChars(v)]) && std.count(std.stringChars(v), '.') <= 1;
  local onOff(v) = std.member(['on', 'off'], v);
  local mysqlFlagValues = {
    binlog_row_image: function(v) std.member(['full', 'minimal', 'noblob'], v),
    innodb_autoinc_lock_mode: function(v) std.member(['0', '1', '2'], v),
    innodb_cloudsql_managed_buffer_pool: onOff,
    innodb_cloudsql_managed_buffer_pool_threshold_pct: function(v) digits(v) && std.parseInt(v) >= 50 && std.parseInt(v) <= 99,
    log_bin_trust_function_creators: onOff,
    log_output: function(v) std.member(['FILE', 'TABLE', 'NONE'], v),
    long_query_time: number,
    performance_schema: onOff,
    performance_schema_max_thread_instances: digits,
    slow_query_log: onOff,
    table_open_cache_instances: function(v) digits(v) && std.parseInt(v) >= 1 && std.parseInt(v) <= 64,
  };
  local mysqlFlags = if std.isArray(cfg.mysql.instance.databaseFlags) then cfg.mysql.instance.databaseFlags else [];
  local mysqlFlagErrors =
    (if std.isArray(cfg.mysql.instance.databaseFlags) then [] else ['mysql.instance.databaseFlags must be a list.'])
    + [
      local name = h.get(f, 'name', '');
      local value = h.get(f, 'value', '');
      'mysql.instance.databaseFlags "%s" must be one of %s, with a valid string value.' % [name, std.join(', ', std.objectFields(mysqlFlagValues))]
      for f in mysqlFlags
      if !std.objectHas(mysqlFlagValues, h.get(f, 'name', '')) || !std.isString(h.get(f, 'value', '')) || !mysqlFlagValues[f.name](f.value)
    ]
    + (local names = [h.get(f, 'name', '') for f in mysqlFlags];
       if std.length(std.set(names)) != std.length(names) then ['mysql.instance.databaseFlags names must be unique.'] else []);
  local names = [h.normalize(h.get(w, 'name', '')) for w in bg.workers + bg.scheduled];
  local duplicates = std.set([n for n in names if std.count(names, n) > 1]);
  local restrictsIdentities = auth.allow.emails != [] || auth.allow.groups != [];
  local usesAuth = auth.required || auth.unauthedPaths != [] || auth.authedPaths != [] || restrictsIdentities;

  // Each route's problems, in the order the chart checks them.
  local checkRoute(i, r) =
    local name = 'routes[%d]' % i;
    local humans = h.get(r, 'humans', '');
    local forge(p) = h.forgePrincipal(cfg, p);
    local isForge(p) = forge(p) != null && h.isForgeName(forge(p).name) && h.isForgeName(forge(p).environment);
    local isPrincipal(p) = isForge(p) || (std.isString(p) && std.startsWith(p, 'spiffe://') && std.length(p) > std.length('spiffe://'));
    (if h.get(r, 'paths', []) == [] then ['%s needs paths.' % name] else [])
    + (if !std.member(['none', 'anyone', 'okta'], humans) then ['%s.humans must be none, anyone or okta.' % name] else [])
    + (if (h.get(r, 'groups', []) != [] || h.get(r, 'emails', []) != []) && humans != 'okta'
       then ['%s sets groups or emails, which only apply with humans: okta.' % name] else [])
    + (if std.objectHas(r, 'apps') then ['%s.apps is now frontierApps.' % name] else [])
    + [
      '%s.principals entry "%s" must be %s (optionally @<environment>) or start with spiffe://.' % [name, p, std.join(', ', ['%s/<forge-app>' % prefix for prefix in std.objectFields(cfg.forgeIdentity.issuers)])]
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
  local delegatedCallers = std.get(cfg, 'delegatedCallers', []);
  // Delegation is trusted only from the Internal Apps signer, under its name or its alias.
  local isForgeCaller(c) =
    local f = h.forgePrincipal(cfg, c);
    f != null && f.prefix == 'forge-internal' && h.isForgeName(f.name) && h.isForgeName(f.environment);
  // Two prefixes sharing an issuer would admit each other's apps.
  local issuers = cfg.forgeIdentity.issuers;
  local issuerErrors = [
    'forgeIdentity.issuers key "%s" must be lowercase letters, digits and hyphens, with an https issuer and a jwks.' % prefix
    for prefix in std.objectFields(issuers)
    if prefix == '' || !std.all([std.member('abcdefghijklmnopqrstuvwxyz0123456789-', c) for c in std.stringChars(prefix)])
       || !std.startsWith(h.get(issuers[prefix], 'issuer', ''), 'https://') || h.get(issuers[prefix], 'jwks', '') == ''
  ] + (
    local urls = [issuers[prefix].issuer for prefix in std.objectFields(issuers)];
    if std.length(std.set(urls)) != std.length(urls) then ['forgeIdentity.issuers must each have their own issuer.'] else []
  ) + (
    if h.delegatedCallers(cfg) != [] && !std.objectHas(issuers, 'forge-internal') then ['delegatedCallers needs the forge-internal issuer in forgeIdentity.issuers.'] else []
  ) + [
    'forgeIdentity.aliases key "%s" must name an issuer key and must not be one itself.' % alias
    for alias in std.objectFields(std.get(cfg.forgeIdentity, 'aliases', {}))
    if std.objectHas(issuers, alias) || !std.objectHas(issuers, cfg.forgeIdentity.aliases[alias])
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
    assert issuerErrors == [] : issuerErrors[0],
    assert routeErrors == [] : routeErrors[0],
    assert std.isArray(delegatedCallers) : 'delegatedCallers must be a list of forge-internal/<forge-app> entries.',
    assert !std.isArray(delegatedCallers) || std.all([isForgeCaller(c) for c in delegatedCallers]) :
           'delegatedCallers entries must be forge-internal/<forge-app>, optionally @<environment> (lowercase letters, digits and hyphens).',

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
    assert !std.objectHas(cfg.mysql.instance, 'profile') :
           'mysql.instance.profile has been replaced by tier and availabilityType.',
    assert std.member(['db-g1-small', 'db-custom-1-3840', 'db-custom-2-7680', 'db-custom-4-15360'], mysqlInstance.tier) :
           'mysql.instance.tier must be db-g1-small, db-custom-1-3840, db-custom-2-7680 or db-custom-4-15360, not "%s".' % mysqlInstance.tier,
    assert std.member(['ZONAL', 'REGIONAL'], mysqlInstance.availabilityType) :
           'mysql.instance.availabilityType must be ZONAL or REGIONAL, not "%s".' % mysqlInstance.availabilityType,
    assert mysqlInstance.tier != 'db-g1-small' || mysqlInstance.availabilityType == 'ZONAL' :
           'mysql.instance.tier db-g1-small cannot be REGIONAL. Raise the tier before turning on high availability.',
    assert std.isNumber(cfg.mysql.instance.diskSize) && std.floor(cfg.mysql.instance.diskSize) == cfg.mysql.instance.diskSize && cfg.mysql.instance.diskSize >= 10 && cfg.mysql.instance.diskSize <= 100 :
           'mysql.instance.diskSize must be a whole number of GB from 10 to 100, not %s.' % cfg.mysql.instance.diskSize,
    assert std.isNumber(cfg.mysql.instance.diskAutoresizeLimit) && std.floor(cfg.mysql.instance.diskAutoresizeLimit) == cfg.mysql.instance.diskAutoresizeLimit && cfg.mysql.instance.diskAutoresizeLimit >= cfg.mysql.instance.diskSize && cfg.mysql.instance.diskAutoresizeLimit <= 100 :
           'mysql.instance.diskAutoresizeLimit must be a whole number of GB from diskSize up to 100.',
    assert std.member(['utf8mb4_0900_ai_ci', 'utf8mb4_unicode_ci'], cfg.mysql.collation) :
           'mysql.collation must be utf8mb4_0900_ai_ci or utf8mb4_unicode_ci, not "%s".' % cfg.mysql.collation,
    assert std.member(['abandon', 'delete'], cfg.mysql.instance.deletionPolicy) :
           'mysql.instance.deletionPolicy must be abandon or delete, not "%s".' % cfg.mysql.instance.deletionPolicy,
    assert !cfg.mysql.enabled || (std.startsWith(cfg.namespace, 'frontier-') && std.length(cfg.namespace) <= 35) :
           'mysql.enabled requires a frontier-* namespace of at most 35 characters so the generated service account id fits.',
    // An older config may still set mysql.projectId: harmless when it matches.
    assert h.get(cfg.mysql, 'projectId', '') == '' || cfg.mysql.projectId == h.mysqlProjectId(cfg) :
           'mysql.projectId "%s" is not this cluster\'s project, %s. Remove mysql.projectId: the cluster sets the project.'
           % [cfg.mysql.projectId, h.mysqlProjectId(cfg)],
    assert h.get(cfg.mysql, 'region', h.mysqlRegion) == h.mysqlRegion :
           'mysql.region is always %s on Frontier. Remove mysql.region.' % h.mysqlRegion,
    assert std.member(['', h.mysqlPrivateNetwork(cfg)], h.get(cfg.mysql, 'privateNetwork', '')) :
           'mysql.privateNetwork is always %s on Frontier. Remove mysql.privateNetwork.' % h.mysqlPrivateNetwork(cfg),
    assert !std.objectHas(cfg.mysql.proxy, 'maxSigtermDelay') :
           'mysql.proxy.maxSigtermDelay is now mysql.proxy.shutdownDelaySeconds, a number of seconds.',
    assert std.isNumber(cfg.mysql.proxy.shutdownDelaySeconds) && std.floor(cfg.mysql.proxy.shutdownDelaySeconds) == cfg.mysql.proxy.shutdownDelaySeconds &&
           cfg.mysql.proxy.shutdownDelaySeconds >= 0 && cfg.mysql.proxy.shutdownDelaySeconds <= 3600 :
           'mysql.proxy.shutdownDelaySeconds must be a whole number of seconds from 0 to 3600.',
    assert std.member(['MYSQL_8_0', 'MYSQL_8_4'], cfg.mysql.version) :
           'mysql.version must be MYSQL_8_0 or MYSQL_8_4, not "%s".' % cfg.mysql.version,
    assert !cfg.mysql.enabled || std.length(std.split(cfg.permissions.owner, '.')) <= h.mysqlOwnerLabelCount :
           'permissions.owner "%s" has more than %d dot-separated parts; Cloud SQL labels cannot store a dotted username in one value.'
           % [cfg.permissions.owner, h.mysqlOwnerLabelCount],
    assert std.isArray(cfg.mysql.databases) && std.isArray(cfg.mysql.users) :
           'mysql.databases and mysql.users must be lists.',
    assert mysqlDbErrors == [] : mysqlDbErrors[0],
    assert mysqlUserErrors == [] : mysqlUserErrors[0],
    assert mysqlConnectionErrors == [] : mysqlConnectionErrors[0],
    assert mysqlFlagErrors == [] : mysqlFlagErrors[0],

    assert !queue.enabled || h.get(queue, 'client', '') == '' || std.objectHas(h.queueClientVars, queue.client) :
           'jobQueue.client "%s" is not one of sidekiq, bullmq and asynq.' % queue.client,
  }
