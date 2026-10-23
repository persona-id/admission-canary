// expect: over DNS's 63; the app name is too long for previews
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.preview({
  appName: 'a-forty-seven-character-repository-name-for-tests-dev',
  namespace: 'frontier-a-forty-seven-character-repository-name-for-tests-dev',
  permissions: { owner: 'owner' },
  image: { repository: 'r', tag: 't' },
}, 12345))
