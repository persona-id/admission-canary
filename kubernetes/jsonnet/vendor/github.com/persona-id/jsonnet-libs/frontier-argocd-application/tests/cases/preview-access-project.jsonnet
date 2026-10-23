// The AppProject for an app's pull request previews' access to dev.
local argocd = import '../../main.libsonnet';

argocd.newPreviewAccessProject('https://github.com/persona-id/my-app')
