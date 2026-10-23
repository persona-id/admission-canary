// Entrypoint make dev renders for skaffold, into the namespace kro creates from
// frontier.jsonnet. See config.libsonnet. To render locally:
//   jsonnet -J ../vendor -y --tla-str user="$USER" main.jsonnet
//
// revision and dirty record where the deploy came from (bin/source-provenance).
// make render reads them once, when make dev starts, so commits made while it
// runs aren't reflected until it restarts.
local app = import '../common/app.libsonnet';
local frontier = import 'github.com/persona-id/jsonnet-libs/frontier-app-base/main.libsonnet';

// kro creates and owns these from the Frontier resource. Developers can't create
// namespaces, and the RoleBindings would duplicate kro's.
local ownedByKro(r) =
  r.kind == 'Namespace'
  || (r.kind == 'RoleBinding'
      && (std.startsWith(r.metadata.name, 'owner-')
          || std.startsWith(r.metadata.name, 'collaborator-')));

function(user, revision='', dirty='')
  local config = (import 'config.libsonnet')(user) + {
    source: { repository: app.repoURL, revision: revision, dirty: dirty },
  };

  // The library leaves namespaces off (ArgoCD sets them from the Application's
  // destination), so set them here.
  [
    r { metadata+: { namespace: config.namespace } }
    for r in frontier.toList(frontier.new(config))
    if !ownedByKro(r)
  ]
