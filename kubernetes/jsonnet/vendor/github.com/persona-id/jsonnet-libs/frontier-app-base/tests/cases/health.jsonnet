// App probes and the PodDisruptionBudget: startupProbe gets the serving port,
// the other probes are passed through, and the budget renders at minScale 2.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  service: { port: 3000 },
  readinessProbe: { httpGet: { path: '/readyz' }, periodSeconds: 5 },
  livenessProbe: { httpGet: { path: '/healthz', port: 3000 } },
  startupProbe: { tcpSocket: {}, failureThreshold: 30 },
  podDisruptionBudget: { enabled: true },
  scaling: { minScale: 2 },
}))
