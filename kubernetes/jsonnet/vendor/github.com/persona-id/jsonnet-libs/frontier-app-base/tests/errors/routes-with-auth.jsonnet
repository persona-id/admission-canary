// expect: routes replaces auth.required
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { routes: [{ paths: ['/*'], humans: 'anyone' }], auth: { required: true } }))
