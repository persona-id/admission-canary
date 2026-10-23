// autoSync=false: no syncPolicy.automated, so ArgoCD only syncs when asked to.
local argocd = import '../../main.libsonnet';

argocd.newFrontierApp(
  'production',
  { namespace: 'frontier-my-app-prod', releaseName: 'frontier-my-app-prod' },
  'https://github.com/persona-id/my-app',
  '>=0.0.0',
  autoSync=false,
)
