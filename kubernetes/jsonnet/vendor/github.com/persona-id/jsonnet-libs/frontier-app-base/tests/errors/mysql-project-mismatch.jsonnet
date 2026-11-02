// expect: mysql.projectId "persona-frontier" is not this cluster's project, persona-frontier-staging. Remove mysql.projectId: the cluster sets the project.
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({
  appName: 'wrong-project',
  namespace: 'frontier-wrong-project-dev',
  gcpProject: 'persona-frontier-staging',
  permissions: { owner: 'owner' },
  mysql: {
    enabled: true,
    projectId: 'persona-frontier',
  },
}))
