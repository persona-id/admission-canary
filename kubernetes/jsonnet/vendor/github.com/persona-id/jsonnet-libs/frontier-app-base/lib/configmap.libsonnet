// ConfigMaps: each Valkey instance's config file.
local h = import 'helpers.libsonnet';
local configMap = (import 'libs.libsonnet').k.core.v1.configMap;

{
  valkey(cfg, instance)::
    configMap.new('%s-config' % instance.name, { 'valkey.conf': instance.conf })
    + configMap.metadata.withLabels(h.valkeyLabels(cfg, instance)),
}
