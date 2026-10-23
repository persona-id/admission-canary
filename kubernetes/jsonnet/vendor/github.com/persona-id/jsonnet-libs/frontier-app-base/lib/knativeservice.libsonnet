// Knative Services (serving.knative.dev/v1 Service): the web service, `app`.
local h = import 'helpers.libsonnet';
local libs = import 'libs.libsonnet';

local container = libs.k.core.v1.container;
local ksvc = libs.knative.serving.v1.service;

// The app container's probes, as configured. Knative fills in a missing port for
// readiness and liveness only, so startupProbe's is set to `service.port`.
local probes(cfg) =
  local liveness = h.get(cfg, 'livenessProbe', {});
  local readiness = h.get(cfg, 'readinessProbe', {});
  local startup = h.get(cfg, 'startupProbe', {});
  (if liveness != {} then { livenessProbe: liveness } else {})
  + (if readiness != {} then { readinessProbe: readiness } else {})
  + (if startup != {} then { startupProbe: startup + {
       [handler]+: { port: cfg.service.port }
       for handler in ['httpGet', 'tcpSocket']
       if std.isObject(std.get(startup, handler)) && !std.objectHas(startup[handler], 'port')
     } } else {});

{
  app(cfg)::
    local placement = h.placement(cfg, cfg.computeClass);
    local volumes = h.podVolumes(cfg);
    local source = h.sourceAnnotations(cfg);
    local annotations =
      source
      + (if cfg.scaling.maxScale > 0 then { 'autoscaling.knative.dev/maxScale': std.toString(cfg.scaling.maxScale) } else {})
      + {
        // At zero the first request comes through the activator, which hides the
        // caller from the app's AuthorizationPolicy.
        'autoscaling.knative.dev/minScale': std.toString(std.max(cfg.scaling.minScale, 1)),
        // Keeps the activator out of the request path; with it in the path every
        // request arrives as the activator and the policy admits everyone.
        'autoscaling.knative.dev/target-burst-capacity': '0',
      };

    ksvc.new('app')
    + (if source != {} then ksvc.metadata.withAnnotations(source) else {})
    + ksvc.metadata.withLabels(
      h.labels(cfg)
      + if cfg.visibility == 'none'
      then { 'networking.knative.dev/visibility': 'cluster-local' }
      else { 'knative.withpersona.com/visibility': cfg.visibility }
    )
    + ksvc.spec.template.metadata.withAnnotations(annotations)
    + ksvc.spec.template.metadata.withLabels(
      { environment: h.environment(cfg) }
      + (if h.oktaAllowlist(cfg) then { 'frontier.withpersona.com/custom-denied-message': 'true' } else {})
    )
    + ksvc.spec.template.spec.withContainers([
      container.withImage(h.appImage(cfg))
      + container.withPorts([libs.k.core.v1.containerPort.new(cfg.service.port)])
      + h.podContainerMixin(cfg)
      + probes(cfg),
    ])
    // Knative drops the node selector and tolerations unless the cluster enables
    // `kubernetes.podspec-nodeselector` and `kubernetes.podspec-tolerations`.
    + (if placement.nodeSelector != {} then ksvc.spec.template.spec.withNodeSelector(placement.nodeSelector) else {})
    + ksvc.spec.template.spec.withServiceAccountName('app')
    + ksvc.spec.template.spec.withTimeoutSeconds(cfg.timeoutSeconds)
    + (if placement.tolerations != [] then ksvc.spec.template.spec.withTolerations(placement.tolerations) else {})
    + (if volumes != [] then ksvc.spec.template.spec.withVolumes(volumes) else {})
    + ksvc.spec.withTraffic([
      ksvc.spec.traffic.withLatestRevision(true)
      + ksvc.spec.traffic.withPercent(100),
    ]),
}
