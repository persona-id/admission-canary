// One-shot Jobs owned by the app deployment.
local h = import 'helpers.libsonnet';

{
  mysqlMigration(cfg)::
    local migration = cfg.mysql.migration;
    local placement = h.placement(cfg, cfg.computeClass);
    local volumes = h.podVolumes(cfg);
    {
      apiVersion: 'batch/v1',
      kind: 'Job',
      metadata: {
        // A Sync hook rather than PreSync: on a first deploy, PreSync would run
        // before the database, ServiceAccount and Secrets it needs exist.
        annotations: {
          'argocd.argoproj.io/hook': 'Sync',
          'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation,HookSucceeded',
          'argocd.argoproj.io/sync-wave': '1',
        },
        labels: h.labels(cfg) {
          'app.kubernetes.io/component': 'mysql-migration',
        },
        name: 'mysql-migrate',
      },
      spec: {
        activeDeadlineSeconds: migration.activeDeadlineSeconds,
        backoffLimit: migration.backoffLimit,
        template: {
          metadata: {
            labels: h.labels(cfg) {
              'app.kubernetes.io/component': 'mysql-migration',
              environment: h.environment(cfg),
            },
          },
          spec: {
            containers: [{
              args: migration.args,
              command: migration.command,
              image: h.appImage(cfg),
              name: 'migration',
            } + h.podContainerMixin(cfg)],
            initContainers: [h.mysqlProxyContainer(cfg, nativeSidecar=true)],
            nodeSelector: placement.nodeSelector,
            restartPolicy: 'Never',
            serviceAccountName: 'app',
            tolerations: placement.tolerations,
            volumes: volumes,
          },
        },
      },
    },
}
