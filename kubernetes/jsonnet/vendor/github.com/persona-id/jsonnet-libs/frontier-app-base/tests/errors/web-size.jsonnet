// expect: service.size "huge" is not one of small, medium and large.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'frontier-demo-dev',
  permissions: { owner: 'owner' },
  image: { repository: 'r', tag: 't' },
  service: { size: 'huge' },
}))
