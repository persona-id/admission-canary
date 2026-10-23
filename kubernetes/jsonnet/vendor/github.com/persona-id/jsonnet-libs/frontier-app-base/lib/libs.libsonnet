// The upstream API libraries, pinned in one place so a version bump is one edit
// here plus `jb install` of the new subdir.
{
  cnrm: import 'github.com/jsonnet-libs/cnrm-libsonnet/1.130/main.libsonnet',
  istio: import 'github.com/jsonnet-libs/istio-libsonnet/1.28/main.libsonnet',
  k: import 'github.com/jsonnet-libs/k8s-libsonnet/1.34/main.libsonnet',
  knative: import 'github.com/jsonnet-libs/knative-serving-libsonnet/1.17.0/main.libsonnet',
}
