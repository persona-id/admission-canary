// The AppProject for an app registered in frontier-app-registry.
local argocd = import '../../main.libsonnet';

argocd.newProject('https://github.com/persona-id/my-app')
