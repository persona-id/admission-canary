// expect: must use lowercase letters, digits and dashes
local argocd = import '../../main.libsonnet';

argocd.newProject('https://github.com/persona-id/My_App')
