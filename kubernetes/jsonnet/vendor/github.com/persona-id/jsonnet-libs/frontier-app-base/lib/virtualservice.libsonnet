// Istio VirtualServices: the route from the Forge listener to the app.
local h = import 'helpers.libsonnet';
local virtualService = (import 'libs.libsonnet').istio.networking.v1.virtualService;

{
  // Sends what the gateway's Forge listener receives for the app's in-cluster
  // name on to the app. The cluster's admission policy admits exactly this shape.
  forge(cfg)::
    local host = 'app.%s.svc.cluster.local' % cfg.namespace;
    virtualService.new('app-forge')
    + virtualService.metadata.withLabels(h.labels(cfg))
    + virtualService.spec.withGateways([cfg.forgeIdentity.gateway])
    + virtualService.spec.withHosts([host])
    + virtualService.spec.withHttp([{ route: [{ destination: { host: host, port: { number: 80 } } }] }]),
}
