// expect: prNumber must be a positive integer, got "4.2
local argocd = import '../../main.libsonnet';

argocd.previewNamespace('https://github.com/persona-id/my-app', 4.2)
