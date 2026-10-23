// Patching the metadata of what newFrontierApp returns keeps its finalizer.
local argocd = import '../../main.libsonnet';

argocd.newFrontierApp(
  'production',
  {
    appName: 'my-app',
    namespace: 'frontier-my-app-prod',
    releaseName: 'frontier-my-app-prod',
  },
  'https://github.com/persona-id/my-app',
  '>=0.0.0',
) + argocd.application.metadata.withLabels({ team: 'x' })
