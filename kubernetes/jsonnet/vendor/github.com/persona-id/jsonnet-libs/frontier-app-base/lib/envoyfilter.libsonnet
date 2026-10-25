// Istio EnvoyFilters: clearing the Forge identity headers on the app's sidecar.
local h = import 'helpers.libsonnet';
local envoyFilter = (import 'libs.libsonnet').istio.networking.v1alpha3.envoyFilter;

// The same Lua as the chart's forge-header-sanitizer.yaml, byte for byte.
local sanitizer = |||
  function envoy_on_request(handle)
    local headers = handle:headers()
    headers:remove("x-forge-caller")
    headers:remove("x-forge-user-email")
    headers:remove("x-forge-user-groups")
    -- Preserve browser oauth2-proxy identity. Forge passes must
    -- never carry an independent caller-supplied Okta identity.
    if headers:get("x-forge-identity") ~= nil then
      headers:remove("x-auth-request-user")
      headers:remove("x-auth-request-email")
      headers:remove("x-auth-request-groups")
      headers:remove("x-auth-request-preferred-username")
      headers:remove("x-auth-request-access-token")
      headers:remove("x-auth-request-redirect")
    end
  end
|||;

{
  // Rendered only with `delegatedCallers`. The VirtualService's header removal
  // covers only the Forge listener, and mapping a claim to a header does not
  // clear a caller-sent one when there is no pass or no such claim, so this runs
  // first (INSERT_FIRST, before jwt_authn and ext_authz) on every inbound HTTP
  // chain of the app's sidecar, whether or not a pass is present. Normal browser
  // oauth2-proxy headers survive unless the request also carries a pass.
  forgeHeaderSanitizer(cfg)::
    envoyFilter.new('app-forge-header-sanitizer')
    + envoyFilter.metadata.withLabels(h.labels(cfg))
    + envoyFilter.spec.workloadSelector.withLabels({ 'serving.knative.dev/service': 'app' })
    + envoyFilter.spec.withConfigPatches([{
      applyTo: 'HTTP_FILTER',
      match: {
        context: 'SIDECAR_INBOUND',
        listener: { filterChain: { filter: { name: 'envoy.filters.network.http_connection_manager' } } },
      },
      patch: {
        operation: 'INSERT_FIRST',
        value: {
          name: 'frontier.filters.http.forge_header_sanitizer',
          typed_config: {
            '@type': 'type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua',
            defaultSourceCode: { inlineString: sanitizer },
          },
        },
      },
    }]),
}
