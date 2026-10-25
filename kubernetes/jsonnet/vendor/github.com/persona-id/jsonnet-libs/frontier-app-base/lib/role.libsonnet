// Roles: the dev Secrets a preview environment's secret reader may get.
local h = import 'helpers.libsonnet';
local k = (import 'libs.libsonnet').k;

local role = k.rbac.v1.role;
local rule = k.rbac.v1.policyRule;

{
  previewSecretReader(cfg, devNamespace)::
    role.new(h.previewSecretReaderRole(cfg))
    + role.metadata.withNamespace(devNamespace)
    + role.metadata.withLabels(h.labels(cfg))
    + role.withRules([
      rule.withApiGroups([''])
      + rule.withResources(['secrets'])
      + rule.withVerbs(['get'])
      + rule.withResourceNames(h.secretNames(cfg)),
    ]),
}
