// OnePasswordItems: secrets synced from 1Password. The operator creates a Secret
// with the same name as each item, one key per field.
// https://developer.1password.com/docs/k8s/operator#kubernetes-secret-from-item
local h = import 'helpers.libsonnet';

// No jsonnet-libs package covers this CRD; shaped like the generated constructors.
local onePasswordItem = {
  metadata:: { withLabels(labels):: { metadata+: { labels: labels } } },
  new(name):: { apiVersion: 'onepassword.com/v1', kind: 'OnePasswordItem', metadata: { name: name } },
  spec:: { withItemPath(itemPath):: { spec+: { itemPath: itemPath } } },
};

{
  // `item` is a `secrets.sources.onePassword.items` entry.
  item(cfg, item)::
    local onePassword = cfg.secrets.sources.onePassword;
    onePasswordItem.new(h.normalize(item.name))
    + onePasswordItem.metadata.withLabels(h.labels(cfg))
    + onePasswordItem.spec.withItemPath('vaults/%s/items/%s' % [h.get(item, 'vaultId', onePassword.defaultVaultId), item.name]),
}
