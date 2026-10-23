// expect: permissions.owner "jane@withpersona.com" must be a username
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'jane@withpersona.com' } }))
