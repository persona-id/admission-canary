// The Frontier resource make bootstrap applies before make dev deploys. kro creates
// the namespace (frontier-<name>) and the owner and collaborator RoleBindings from
// it, as the kro controller. Developers can create Frontier resources in
// frontier-system but can't create namespaces themselves, so this is what gives
// them one.
//
// `user` only names the namespace. `owner` is the Persona username (without
// @withpersona.com) of the developer running make dev, which make bootstrap reads
// from `kubectl auth whoami`, so the namespace is theirs. The app's owner and
// collaborators from common/config.libsonnet keep access as collaborators. To
// render locally:
//   jsonnet -J ../vendor --tla-str user="$USER" --tla-str owner="$USER" frontier.jsonnet
function(user, owner)
  // The pattern the Frontier resource's spec.owner accepts.
  assert std.length(owner) > 0
         && std.all([
           std.member('abcdefghijklmnopqrstuvwxyz0123456789-.', c)
           for c in std.stringChars(owner)
         ]) :
         'owner must be a Persona username of lowercase letters, digits, - and ., without @withpersona.com, got "%s"' % owner;

  local config = (import 'config.libsonnet')(user);
  local permissions = std.get(config, 'permissions', {});
  local appUsers =
    [permissions.owner] + std.get(permissions, 'additionalCollaborators', []);

  {
    apiVersion: 'frontier.withpersona.com/v1alpha1',
    kind: 'Frontier',
    metadata: {
      name: config.appName,
      namespace: 'frontier-system',
    },
    spec: {
      name: config.appName,
      owner: owner,
      collaborators: std.set([u for u in appUsers if u != owner]),
      catalog: std.get(std.get(config, 'homestead', {}), 'catalog', 'prod'),
    },
  }
