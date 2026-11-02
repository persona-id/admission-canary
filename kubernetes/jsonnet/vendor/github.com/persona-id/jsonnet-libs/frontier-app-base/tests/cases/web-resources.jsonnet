// The web container sized like a Rails app: the medium tier with its requests
// raised, so `service.resources` merges over `service.size`.
local frontier = import '../../main.libsonnet';

local objects = frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'frontier-demo-prod',
  permissions: { owner: 'owner' },
  image: { repository: 'r', tag: 't' },
  service: {
    port: 4000,
    size: 'medium',
    resources: { requests: { cpu: '1', memory: '2Gi' }, limits: { memory: '4Gi' } },
  },
  scaling: { minScale: 3 },
}));

[o for o in objects if o.kind == 'Service' && o.apiVersion == 'serving.knative.dev/v1']
