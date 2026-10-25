// Istio VirtualServices: the route from the Forge listener to the app.
local h = import 'helpers.libsonnet';
local virtualService = (import 'libs.libsonnet').istio.networking.v1.virtualService;

// Identity headers only oauth2-proxy or a verified pass may set, which a Forge
// app acting for a person must not send itself. The same list as the chart's.
local identityHeaders = [
  'x-auth-request-user',
  'x-auth-request-email',
  'x-auth-request-groups',
  'x-auth-request-preferred-username',
  'x-auth-request-access-token',
  'x-auth-request-redirect',
  'x-forge-caller',
  'x-forge-user-email',
  'x-forge-user-groups',
];

{
  // Sends what the gateway's Forge listener receives for the app's in-cluster
  // name on to the app. The cluster's admission policy admits exactly this shape.
  // With `delegatedCallers` it also drops the identity headers a caller sent.
  forge(cfg)::
    local host = 'app.%s.svc.cluster.local' % cfg.namespace;
    virtualService.new('app-forge')
    + virtualService.metadata.withLabels(h.labels(cfg))
    + virtualService.spec.withGateways([cfg.forgeIdentity.gateway])
    + virtualService.spec.withHosts([host])
    + virtualService.spec.withHttp([
      (if h.delegatedCallers(cfg) != [] then { headers: { request: { remove: identityHeaders } } } else {})
      + { route: [{ destination: { host: host, port: { number: 80 } } }] },
    ]),
}
