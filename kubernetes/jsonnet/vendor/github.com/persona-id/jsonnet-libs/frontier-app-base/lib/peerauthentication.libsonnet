// Istio PeerAuthentications: STRICT mTLS for the app and each Valkey instance.
local h = import 'helpers.libsonnet';
local istio = (import 'libs.libsonnet').istio;

{
  // STRICT is a prerequisite, not hardening: without it Knative's autoscaler and
  // activator reach the pod by pod IP, which Istio never mTLS's, so they arrive
  // with no principal and no identity rule in the app's AuthorizationPolicy can
  // match them.
  app(cfg)::
    local peerAuthentication = istio.security.v1.peerAuthentication;
    peerAuthentication.new('app-mtls-strict')
    + peerAuthentication.metadata.withLabels(h.labels(cfg))
    + peerAuthentication.spec.mtls.withMode('STRICT')
    + peerAuthentication.spec.selector.withMatchLabels({ 'serving.knative.dev/service': 'app' }),

  valkey(cfg, instance)::
    local peerAuthentication = istio.security.v1beta1.peerAuthentication;
    peerAuthentication.new('%s-mtls-strict' % instance.name)
    + peerAuthentication.metadata.withLabels(h.labels(cfg))
    + peerAuthentication.spec.mtls.withMode('STRICT')
    + peerAuthentication.spec.selector.withMatchLabels({ 'app.kubernetes.io/name': instance.name }),
}
