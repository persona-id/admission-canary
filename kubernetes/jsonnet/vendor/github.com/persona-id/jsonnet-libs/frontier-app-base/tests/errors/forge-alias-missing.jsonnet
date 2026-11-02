// expect: forgeIdentity.aliases key "old" must name an issuer key and must not be one itself.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { forgeIdentity: { aliases: { old: 'forge-gone' } } }))
