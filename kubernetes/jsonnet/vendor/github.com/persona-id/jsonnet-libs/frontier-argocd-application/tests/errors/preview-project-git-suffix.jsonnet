// expect: without a .git suffix
local argocd = import '../../main.libsonnet';

argocd.newPreviewProject('https://github.com/persona-id/my-app.git')
