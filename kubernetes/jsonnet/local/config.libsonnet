// Config for a developer's local deploy (make dev): the development config, renamed
// for a per-developer namespace, frontier-<app>-dev-<user>, that ArgoCD doesn't
// manage. The development Application owns frontier-<app>-dev with prune and
// selfHeal on, so a local deploy there would be reverted.
//
// development/secrets.libsonnet is left out: those secrets are sealed for the
// development namespace and won't decrypt in this one.
local development = import '../development/config.libsonnet';

function(user)
  assert user != '' : 'user is required';

  local appName = development.appName + '-' + user;
  std.foldl(std.mergePatch, [
    import '../common/config.libsonnet',
    development,
    {
      appName: appName,
      // kro names the namespace frontier-<Frontier name>; see frontier.jsonnet.
      namespace: 'frontier-' + appName,
      releaseName: 'frontier-' + appName,
      managedBy: 'skaffold',
      // A placeholder. skaffold replaces the image with the one it built.
      image: { tag: 'skaffold' },
    },
  ], {})
