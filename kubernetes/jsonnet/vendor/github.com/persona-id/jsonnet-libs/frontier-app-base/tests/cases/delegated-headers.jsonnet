// The header contract alone: the claims mapped to headers, the identity headers
// the Forge route removes, and the sidecar EnvoyFilter that clears them first.
local frontier = import '../../main.libsonnet';

local rendered = frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  delegatedCallers: ['forge/persona-cf-app-oracle'],
  routes: [{ paths: ['/*'], humans: 'okta' }],
});

[rendered.forgeRequestAuthentication, rendered.forgeVirtualService, rendered.forgeHeaderSanitizer]
