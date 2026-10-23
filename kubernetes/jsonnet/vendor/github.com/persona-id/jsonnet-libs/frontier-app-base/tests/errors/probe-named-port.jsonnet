// expect: startupProbe.tcpSocket.port is http; Knative only probes the serving port
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { startupProbe: { tcpSocket: { port: 'http' } } }))
