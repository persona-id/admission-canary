// expect: repoURL must be https://github.com/persona-id/<repository> without a .git suffix
local argocd = import '../../main.libsonnet';

argocd.newFrontierApp('production', { appName: 'my-app', namespace: 'frontier-my-app-prod' }, 'https://github.com/persona-id/my-app.git', '>=0.0.0')
