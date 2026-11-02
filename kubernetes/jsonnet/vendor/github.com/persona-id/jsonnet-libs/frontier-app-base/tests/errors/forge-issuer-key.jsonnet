// expect: forgeIdentity.issuers key "Forge_Partner" must be lowercase letters, digits and hyphens
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { forgeIdentity: { issuers: { Forge_Partner: { issuer: 'https://partner.example', jwks: '{"keys":[]}' } } } }))
