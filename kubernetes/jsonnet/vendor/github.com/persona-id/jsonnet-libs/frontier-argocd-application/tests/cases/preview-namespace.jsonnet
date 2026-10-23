// A preview's namespace, from a pull request number given as a string, as Argo CD passes it.
local argocd = import '../../main.libsonnet';

{
  apiVersion: 'v1',
  kind: 'Namespace',
  metadata: { name: argocd.previewNamespace('https://github.com/persona-id/my-app', '42') },
}
