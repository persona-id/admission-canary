// SecretStores: a preview environment's, which reads its dev app's Secrets.
local h = import 'helpers.libsonnet';

{
  previewDev(cfg, devNamespace):: {
    apiVersion: 'external-secrets.io/v1',
    kind: 'SecretStore',
    metadata: { name: h.previewSecretStore, labels: h.labels(cfg) },
    spec: {
      provider: {
        kubernetes: {
          remoteNamespace: devNamespace,
          server: { caProvider: { type: 'ConfigMap', name: 'kube-root-ca.crt', key: 'ca.crt' } },
          auth: { serviceAccount: { name: h.previewSecretReader } },
        },
      },
    },
  },
}
