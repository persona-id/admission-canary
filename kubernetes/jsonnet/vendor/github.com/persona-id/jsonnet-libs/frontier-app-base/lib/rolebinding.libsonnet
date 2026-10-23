// RoleBindings that let people manage the app's namespace: its owner and each
// collaborator get the built-in `edit` ClusterRole, plus `frontier-namespace-owner`
// (defined in persona-kubernetes) for the kinds `edit` leaves out.
local h = import 'helpers.libsonnet';
local k = (import 'libs.libsonnet').k;

local roleBinding = k.rbac.v1.roleBinding;
local subject = k.rbac.v1.subject;

local bind(cfg, name, clusterRole, user) =
  roleBinding.new(name)
  + roleBinding.metadata.withLabels(h.labels(cfg))
  + roleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io')
  + roleBinding.roleRef.withKind('ClusterRole')
  + roleBinding.roleRef.withName(clusterRole)
  + roleBinding.withSubjects([
    subject.withApiGroup('rbac.authorization.k8s.io')
    + subject.withKind('User')
    + subject.withName('%s@withpersona.com' % user),
  ]);

{
  ownerEdit(cfg):: bind(cfg, 'owner-edit', 'edit', cfg.permissions.owner),
  ownerCrdAccess(cfg):: bind(cfg, 'owner-crd-access', 'frontier-namespace-owner', cfg.permissions.owner),

  collaboratorEdit(cfg, user):: bind(cfg, 'collaborator-edit-%s' % user, 'edit', user),
  collaboratorCrdAccess(cfg, user)::
    bind(cfg, 'collaborator-crd-access-%s' % user, 'frontier-namespace-owner', user),
}
