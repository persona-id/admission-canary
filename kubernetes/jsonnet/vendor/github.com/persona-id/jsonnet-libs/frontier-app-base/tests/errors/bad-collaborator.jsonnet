// expect: permissions.additionalCollaborators entry "Sam" must be a username
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner', additionalCollaborators: ['ok', 'Sam'] } }))
