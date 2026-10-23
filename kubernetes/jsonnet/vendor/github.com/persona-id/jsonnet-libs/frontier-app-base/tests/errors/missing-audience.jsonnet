// expect: audience is required
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { serviceAccountTokens: [{ name: 't', mountPath: '/t' }] }))
