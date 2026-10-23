// The AppProject for the pull request previews of an app registered in frontier-app-registry.
local argocd = import '../../main.libsonnet';

argocd.newPreviewProject('https://github.com/persona-id/my-app')
