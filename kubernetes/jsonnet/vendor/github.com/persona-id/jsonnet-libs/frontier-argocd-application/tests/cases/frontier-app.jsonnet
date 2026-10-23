// A repo built from persona-template-frontier-app, its production environment
// following releases.
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
)
