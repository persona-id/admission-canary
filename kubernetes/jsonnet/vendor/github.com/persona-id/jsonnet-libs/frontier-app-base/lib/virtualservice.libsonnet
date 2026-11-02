// Istio VirtualServices: the route from the Forge listener to the app.
local h = import 'helpers.libsonnet';
local virtualService = (import 'libs.libsonnet').istio.networking.v1.virtualService;

// Identity headers only oauth2-proxy or a verified pass may set, which a Forge
// caller must not send itself: oauth2-proxy doesn't run on the Forge route, so a
// caller-sent `x-auth-request-email` would reach the app as the signed-in
// person. The chart's list, plus `x-forge-app` and `x-forge-environment`, which
// the chart does not map. Mapping a claim to a header leaves a caller-sent copy
// in place when the pass lacks the claim, so those are removed too.
local identityHeaders = [
  'x-auth-request-user',
  'x-auth-request-email',
  'x-auth-request-groups',
  'x-auth-request-preferred-username',
  'x-auth-request-access-token',
  'x-auth-request-redirect',
  'x-forge-caller',
  'x-forge-issuer',
  'x-forge-user-email',
  'x-forge-user-groups',
  'x-forge-app',
  'x-forge-environment',
];

{
  // Sends what the gateway's Forge listener receives for the app's in-cluster
  // name on to the app, dropping every identity header a caller sent, as the
  // chart does for every app with Forge callers. The cluster's admission policy
  // admits exactly this shape.
  forge(cfg)::
    local host = 'app.%s.svc.cluster.local' % cfg.namespace;
    virtualService.new('app-forge')
    + virtualService.metadata.withLabels(h.labels(cfg))
    + virtualService.spec.withGateways([cfg.forgeIdentity.gateway])
    + virtualService.spec.withHosts([host])
    + virtualService.spec.withHttp([
      { headers: { request: { remove: identityHeaders } } }
      + { route: [{ destination: { host: host, port: { number: 80 } } }] },
    ]),
}
