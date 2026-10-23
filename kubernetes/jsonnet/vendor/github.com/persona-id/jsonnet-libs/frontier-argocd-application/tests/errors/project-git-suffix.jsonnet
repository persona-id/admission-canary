// expect: without a .git suffix
local argocd = import '../../main.libsonnet';

argocd.newProject('https://github.com/persona-id/my-app.git')
