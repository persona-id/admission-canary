// DomainMappings: the custom domains the app is also reachable on.
// https://knative.dev/docs/serving/services/custom-domains
local h = import 'helpers.libsonnet';
local domainMapping = (import 'libs.libsonnet').knative.serving.v1beta1.domainMapping;

{
  // `item` is a `customDomains` entry.
  customDomain(cfg, item)::
    domainMapping.new(item.fqdn)
    + domainMapping.metadata.withLabels(h.labels(cfg))
    + domainMapping.spec.ref.withApiVersion('serving.knative.dev/v1')
    + domainMapping.spec.ref.withKind('Service')
    + domainMapping.spec.ref.withName('app'),
}
