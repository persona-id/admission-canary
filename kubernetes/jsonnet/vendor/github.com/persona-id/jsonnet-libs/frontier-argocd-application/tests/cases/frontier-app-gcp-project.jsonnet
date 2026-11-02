// The cluster's Argo CD passed its GCP project to kubernetes/deploy, which
// forwards it to main.jsonnet for frontier-app-base's managed MySQL.
local argocd = import '../../main.libsonnet';

argocd.newFrontierApp(
  'development',
  {
    appName: 'my-app',
    namespace: 'frontier-my-app-dev',
  },
  'https://github.com/persona-id/my-app',
  'main',
  gcpProject='persona-frontier-staging',
)
