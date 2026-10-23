// prod sealed secrets, sealed for this app's frontier-<name>-prod namespace and
// merged over production/config.libsonnet.
//
// Written by bin/create-secret; edits here are overwritten. Each item:
//   { name, ciphertext, envVar?, mountPath? }
// A ciphertext only decrypts in the namespace it was sealed for, so a secret
// needed in both environments must be sealed once for each.
{
  secrets: {
    sources: {
      sealedSecrets: {
        items: [],
      },
    },
  },
}
