// Entrypoint ArgoCD renders for the production Application
// (kubernetes/deploy/production.jsonnet). Layers are deep-merged in order, the way
// Helm merges value files: objects merge key by key, lists and scalars replace.
//
// imageTag is a top-level argument: the Application passes the commit sha of the release it deployed,
// which .github/workflows/release.yaml pushed the image under. To render locally:
//   jsonnet -J ../vendor --tla-str imageTag="$(git rev-parse HEAD)" main.jsonnet
local app = import '../common/app.libsonnet';
local frontier = import 'github.com/persona-id/jsonnet-libs/frontier-app-base/main.libsonnet';

function(imageTag)
  local config = std.foldl(std.mergePatch, [
    import '../common/config.libsonnet',
    import 'config.libsonnet',
    import 'secrets.libsonnet',
    {
      image: { tag: imageTag },
      // Where the deploy came from. ArgoCD renders a commit, so it's never dirty.
      source: { repository: app.repoURL, revision: imageTag, dirty: false },
    },
  ], {});

  frontier.toList(frontier.new(config))
