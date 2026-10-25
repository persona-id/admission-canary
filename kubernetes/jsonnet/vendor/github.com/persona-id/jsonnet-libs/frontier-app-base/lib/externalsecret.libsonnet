// ExternalSecrets: a preview environment's copies of its dev app's Secrets.
local h = import 'helpers.libsonnet';

{
  previewDev(cfg, name):: {
    apiVersion: 'external-secrets.io/v1',
    kind: 'ExternalSecret',
    metadata: { name: name, labels: h.labels(cfg) },
    spec: {
      refreshInterval: '1h',
      secretStoreRef: { kind: 'SecretStore', name: h.previewSecretStore },
      target: { name: name, creationPolicy: 'Owner' },
      dataFrom: [{ extract: { key: name } }],
    },
  },
}
