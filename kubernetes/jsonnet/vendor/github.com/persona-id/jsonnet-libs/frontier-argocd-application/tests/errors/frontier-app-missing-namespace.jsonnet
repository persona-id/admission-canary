// expect: config needs a namespace
local argocd = import '../../main.libsonnet';

argocd.newFrontierApp('production', { appName: 'my-app' }, 'https://github.com/persona-id/my-app', '>=0.0.0')
