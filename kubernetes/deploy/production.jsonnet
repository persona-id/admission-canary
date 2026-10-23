// The production Application. To render it:
//   cd kubernetes/deploy && jsonnet -J ../jsonnet/vendor production.jsonnet
//
// newFrontierApp renders kubernetes/jsonnet/production/main.jsonnet. The Application's
// name and destination namespace come from that environment's config.libsonnet
// (releaseName and namespace), so the resources ArgoCD renders and the Application
// tracking them can't drift apart.
local app = import '../jsonnet/common/app.libsonnet';
local argocd = import 'github.com/persona-id/jsonnet-libs/frontier-argocd-application/main.libsonnet';

argocd.newFrontierApp(
  'production',
  import '../jsonnet/production/config.libsonnet',
  app.repoURL,
  // Production follows releases, not main: ArgoCD resolves this semver range to
  // the highest matching tag. .github/workflows/release.yaml publishes one
  // after each merge to main and pushes the image under the tag's commit sha.
  // Prerelease tags (v1.2.0-rc.1) never match. With no matching tag at all, the
  // Application errors rather than deploying.
  //
  // The tag has to be lightweight (what GitHub Releases create): for an
  // annotated tag the sha ArgoCD resolves may be the tag object's, which has no
  // image.
  targetRevision='>=0.0.0',
)
