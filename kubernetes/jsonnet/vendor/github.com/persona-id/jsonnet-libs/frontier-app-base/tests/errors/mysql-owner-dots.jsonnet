// expect: permissions.owner "a.b.c.d.e.f.g" has more than 6 dot-separated parts
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'too-many-dots',
  namespace: 'frontier-too-many-dots-dev',
  permissions: { owner: 'a.b.c.d.e.f.g' },
  mysql: {
    enabled: true,
    projectId: 'persona-frontier-staging',
  },
}))
