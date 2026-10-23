// expect: must be at most 47 characters
local argocd = import '../../main.libsonnet';

argocd.newProject('https://github.com/persona-id/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
