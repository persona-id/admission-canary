// delegatedCallers on an app whose routes all say humans: none: no delegated rule
// at all, while a Forge app named in principals keeps exactly its service rule.
// The pass verification, Forge route and sanitizer are still rendered.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  visibility: 'none',
  delegatedCallers: ['forge/persona-cf-app-oracle'],
  routes: [{ paths: ['/*'], humans: 'none', principals: ['forge/service', 'spiffe://cluster.local/ns/peer/sa/app'] }],
}))
