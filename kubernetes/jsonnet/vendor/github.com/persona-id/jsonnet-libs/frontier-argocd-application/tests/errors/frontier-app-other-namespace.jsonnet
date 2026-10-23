// expect: config's namespace must be frontier-my-app-dev or frontier-my-app-prod, the namespaces project frontier-my-app allows, got frontier-other-app-prod
local argocd = import '../../main.libsonnet';

argocd.newFrontierApp('production', { appName: 'my-app', namespace: 'frontier-other-app-prod' }, 'https://github.com/persona-id/my-app', '>=0.0.0')
