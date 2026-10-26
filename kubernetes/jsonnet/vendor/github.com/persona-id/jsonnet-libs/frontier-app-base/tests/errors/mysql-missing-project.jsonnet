// expect: mysql.projectId must not be empty when mysql.enabled is true.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'missing-project',
  namespace: 'frontier-missing-project-dev',
  permissions: { owner: 'owner' },
  mysql: { enabled: true, projectId: '' },
}))
