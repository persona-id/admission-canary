// delegatedCallers on a humans: anyone route: any pass from a listed app with the
// marker and an email gets in, with no domain restriction. Not Oracle, so no
// oracle-access label.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  delegatedCallers: ['forge/other-app'],
  routes: [{ paths: ['/*'], humans: 'anyone' }],
}))
