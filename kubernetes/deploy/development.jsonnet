// The development Application. To render it:
//   cd kubernetes/deploy && jsonnet -J ../jsonnet/vendor development.jsonnet
//
// newFrontierApp renders kubernetes/jsonnet/development/main.jsonnet. The Application's
// name and destination namespace come from that environment's config.libsonnet
// (releaseName and namespace), so the resources ArgoCD renders and the Application
// tracking them can't drift apart.
local app = import '../jsonnet/common/app.libsonnet';
local argocd = import 'github.com/persona-id/jsonnet-libs/frontier-argocd-application/main.libsonnet';

argocd.newFrontierApp(
  'development',
  import '../jsonnet/development/config.libsonnet',
  app.repoURL,
  // Development follows the frontier-dev branch, not releases. AI Dev pushes
  // there, and .github/workflows/sync-frontier-dev.yaml merges main into it
  // after every merge to main. .github/workflows/deploy-dev.yaml pushes the
  // image under each frontier-dev commit sha.
  targetRevision='frontier-dev',
)
