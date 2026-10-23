// A mostly public app: only `authedPaths` go through SSO, with no compute class.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  auth: { required: true, authedPaths: ['/admin/*'], allow: { groups: ['G'] } },
  computeClass: '',
}))
