// expect: targetRevision is required
local argocd = import '../../main.libsonnet';

argocd.newFrontierApp('production', { appName: 'my-app', namespace: 'frontier-my-app-prod' }, 'https://github.com/persona-id/my-app', '')
