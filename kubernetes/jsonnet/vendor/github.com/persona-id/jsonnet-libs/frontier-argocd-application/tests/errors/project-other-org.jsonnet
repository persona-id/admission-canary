// expect: repoURL must be https://github.com/persona-id/<repository>
local argocd = import '../../main.libsonnet';

argocd.newProject('https://github.com/someone-else/my-app')
