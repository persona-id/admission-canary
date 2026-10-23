// expect: does not exist: new
local argocd = import '../../main.libsonnet';

argocd.new('my-app', 'frontier-my-app-prod', 'https://github.com/persona-id/my-app', 'deploy', 'main')
