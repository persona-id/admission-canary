// expect: readinessProbe.httpGet.port is 9090; Knative only probes the serving port
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { readinessProbe: { httpGet: { path: '/readyz', port: 9090 } } }))
