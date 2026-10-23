// Without releaseName the Application is named after appName, as frontier-app-base
// defaults releaseName to it.
local argocd = import '../../main.libsonnet';

argocd.newFrontierApp(
  'development',
  { appName: 'my-app-dev', namespace: 'frontier-my-app-dev' },
  'https://github.com/persona-id/my-app',
  'frontier-dev',
)
