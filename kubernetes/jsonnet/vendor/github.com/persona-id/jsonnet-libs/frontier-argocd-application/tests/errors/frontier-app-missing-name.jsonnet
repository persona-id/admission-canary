// expect: config needs a releaseName or appName
local argocd = import '../../main.libsonnet';

argocd.newFrontierApp('production', { namespace: 'frontier-my-app-prod' }, 'https://github.com/persona-id/my-app', '>=0.0.0')
