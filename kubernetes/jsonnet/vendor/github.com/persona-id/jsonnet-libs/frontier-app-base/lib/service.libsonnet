// Services: each Valkey instance's address, e.g. redis://valkey:6379. The web
// service is a Knative Service; see knativeservice.libsonnet.
local h = import 'helpers.libsonnet';
local k = (import 'libs.libsonnet').k;

local service = k.core.v1.service;
local servicePort = k.core.v1.servicePort;

{
  valkey(cfg, instance)::
    service.new(
      instance.name,
      h.valkeySelector(cfg, instance),
      [servicePort.newNamed('tcp', h.valkeyPort, 'tcp') + servicePort.withProtocol('TCP')],
    )
    + service.metadata.withLabels(h.valkeyLabels(cfg, instance))
    + service.spec.withType('ClusterIP'),
}
