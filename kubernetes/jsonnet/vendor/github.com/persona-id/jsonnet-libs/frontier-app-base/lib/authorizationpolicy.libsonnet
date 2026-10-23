// Istio AuthorizationPolicies: who may reach which of the app's paths, the SSO
// gate in front of the Okta routes, the allowance for the app's own namespace,
// and the rule letting only `app` reach each Valkey instance.
local h = import 'helpers.libsonnet';
local istio = (import 'libs.libsonnet').istio;

local appSelector = { 'serving.knative.dev/service': 'app' };

// Humans arrive as one of the ingress gateways. Listing a gateway with no route
// to the app admits nothing, so both are listed for every app.
local gateways = [
  'cluster.local/ns/istio-gateways/sa/istio-ingressgateway-internal',
  'cluster.local/ns/istio-gateways/sa/istio-ingressgateway-external',
];

// A route's Istio operation, from the `operation` helpers.routes gives it,
// skipping `notHosts` when given.
local operation(rule, route, notHosts=[]) =
  rule.to.operation.withPaths(route.operation.paths)
  + (if std.objectHas(route.operation, 'notPaths') then rule.to.operation.withNotPaths(route.operation.notPaths) else {})
  + (if notHosts != [] then rule.to.operation.withNotHosts(notHosts) else {});

// Whether a route lists callers besides humans.
local hasCallers(route) = route.frontierApps != [] || route.principals != [];

// `std.uniq` only drops adjacent repeats; this keeps the first of each.
local uniq(xs) = std.foldl(function(acc, x) if std.member(acc, x) then acc else acc + [x], xs, []);

{
  // Default-deny for the app: one ALLOW rule per route and audience, so a path no
  // route claims matches no rule and is refused. Knative's own components are
  // always admitted.
  app(cfg)::
    local authorizationPolicy = istio.security.v1.authorizationPolicy;
    local rule = authorizationPolicy.spec.rules;
    local humansReach = cfg.visibility != 'none';
    local to(route) = rule.withTo([operation(rule, route)]);
    local from(principals) = rule.withFrom([rule.from.source.withPrincipals(principals)]);
    // Forge requests arrive as the internal gateway, like people, so only the
    // pass tells them apart; a pass holder is admitted by a route that names it.
    local fromPeople = rule.withFrom([
      rule.from.source.withPrincipals(gateways)
      + rule.from.source.withNotRequestPrincipals([cfg.forgeIdentity.issuer + '/*']),
    ]);
    local fromForge(apps) = rule.withFrom([
      rule.from.source.withPrincipals([cfg.forgeIdentity.gatewayPrincipal])
      + rule.from.source.withRequestPrincipals([cfg.forgeIdentity.issuer + '/' + a for a in apps]),
    ]);

    // Where Okta is skipped for the in-cluster names, gateway traffic to those
    // names is not a person: knative-local-gateway routes them on the same
    // gateway pods for callers without a sidecar.
    local humanRules(route) =
      local claims = if route.humans == 'okta' then { email: route.emails, groups: route.groups } else {};
      local toPeople = rule.withTo([operation(rule, route, if route.humans == 'okta' && hasCallers(route) then h.inClusterHosts(cfg) else [])]);
      if !humansReach || route.humans == 'none' then []
      // Conditions in one rule are ANDed, so an Okta allowlist is one rule per claim.
      else if std.any([claims[c] != [] for c in std.objectFields(claims)]) then [
        fromPeople + toPeople
        + rule.withWhen([rule.when.withKey('request.auth.claims[%s]' % c) + rule.when.withValues(claims[c])])
        for c in std.objectFields(claims)
        if claims[c] != []
      ]
      else [fromPeople + toPeople];

    // `cluster.local` matches regardless of the mesh's real trust domain, since
    // Istio aliases it. Every Frontier workload runs as `sa/app` in its namespace.
    local callerRules(route) =
      local callers = uniq(
        ['cluster.local/ns/%s/sa/app' % ns for ns in route.frontierApps]
        + [std.substr(p, std.length('spiffe://'), std.length(p)) for p in route.principals if std.startsWith(p, 'spiffe://')]
      );
      if callers == [] then [] else [from(callers) + to(route)];

    // Forge apps arrive through the gateway's Forge listener carrying a pass.
    local forgeRules(route) =
      local apps = uniq([std.substr(p, std.length('forge/'), std.length(p)) for p in route.principals if std.startsWith(p, 'forge/')]);
      if apps == [] then [] else [fromForge(apps) + to(route)];

    authorizationPolicy.new('app-s2s')
    + authorizationPolicy.metadata.withLabels(h.labels(cfg))
    + authorizationPolicy.spec.selector.withMatchLabels(appSelector)
    + authorizationPolicy.spec.withAction('ALLOW')
    + authorizationPolicy.spec.withRules(
      std.flatMap(function(route) humanRules(route) + callerRules(route) + forgeRules(route), h.routes(cfg))
      // Denying these leaves the app serving but unable to scale.
      + [from(['cluster.local/ns/knative-serving/sa/activator', 'cluster.local/ns/knative-serving/sa/controller'])]
    ),

  // Unselected on purpose: MySQL, Postgres and standalone Redis carry no policy of
  // their own, and this covers workloads added later. Identity-based, so it also
  // works for plain TCP.
  intraNamespace(cfg)::
    local authorizationPolicy = istio.security.v1.authorizationPolicy;
    local rule = authorizationPolicy.spec.rules;

    authorizationPolicy.new('allow-intra-namespace')
    + authorizationPolicy.metadata.withLabels(h.labels(cfg))
    + authorizationPolicy.spec.withAction('ALLOW')
    + authorizationPolicy.spec.withRules([
      rule.withFrom([rule.from.source.withNamespaces([cfg.namespace])]),
    ]),

  // Hands requests on the `okta` routes to oauth2-proxy, which redirects
  // unauthenticated callers to Okta. Callers addressing the in-cluster names skip
  // it, keyed on host because CUSTOM rejects source fields; app-s2s then admits
  // only the listed callers there.
  requireAuth(cfg)::
    local authorizationPolicy = istio.security.v1.authorizationPolicy;
    local rule = authorizationPolicy.spec.rules;

    authorizationPolicy.new('app-require-auth')
    + authorizationPolicy.metadata.withLabels(h.labels(cfg))
    + authorizationPolicy.spec.provider.withName('oauth2-proxy')
    + authorizationPolicy.spec.selector.withMatchLabels(appSelector)
    + authorizationPolicy.spec.withAction('CUSTOM')
    + authorizationPolicy.spec.withRules([
      rule.withTo([operation(rule, route, if hasCallers(route) then h.inClusterHosts(cfg) else [])])
      for route in h.routes(cfg)
      if route.humans == 'okta'
    ]),

  // Admits only the `app` ServiceAccount. Trust is namespace-scoped: anything
  // running as `app` can reach the instance. The cache also admits its own
  // ServiceAccount, the identity a replica syncs from the primary as.
  valkey(cfg, instance)::
    local authorizationPolicy = istio.security.v1beta1.authorizationPolicy;
    local rule = authorizationPolicy.spec.rules;

    authorizationPolicy.new('%s-allow-app' % instance.name)
    + authorizationPolicy.metadata.withLabels(h.labels(cfg))
    + authorizationPolicy.spec.selector.withMatchLabels({ 'app.kubernetes.io/name': instance.name })
    + authorizationPolicy.spec.withAction('ALLOW')
    + authorizationPolicy.spec.withRules([
      rule.withFrom([rule.from.source.withPrincipals(
        [h.appPrincipal(cfg)]
        + (if instance.name == 'valkey' then ['cluster.local/ns/%s/sa/valkey' % cfg.namespace] else [])
      )]),
    ]),
}
