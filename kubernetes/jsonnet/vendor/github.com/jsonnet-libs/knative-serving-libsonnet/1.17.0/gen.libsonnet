{
  local d = (import 'doc-util/main.libsonnet'),
  '#':: d.pkg(name='knative-serving', url='github.com/jsonnet-libs/knative-serving-libsonnet/1.17.0/main.libsonnet', help=''),
  autoscaling:: (import '_gen/autoscaling/main.libsonnet'),
  caching:: (import '_gen/caching/main.libsonnet'),
  networking:: (import '_gen/networking/main.libsonnet'),
  serving:: (import '_gen/serving/main.libsonnet'),
}
