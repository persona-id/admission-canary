{
  local d = (import 'doc-util/main.libsonnet'),
  '#':: d.pkg(name='v1', url='', help=''),
  configuration: (import 'configuration.libsonnet'),
  revision: (import 'revision.libsonnet'),
  route: (import 'route.libsonnet'),
  service: (import 'service.libsonnet'),
}
