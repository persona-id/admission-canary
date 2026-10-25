// Istio RequestAuthentications: verification of the Okta ID token.
local h = import 'helpers.libsonnet';
local requestAuthentication = (import 'libs.libsonnet').istio.security.v1.requestAuthentication;

{
  // Verifies the pass the identity service signs for each Forge request. The
  // audience pins a pass to this app. Rendered only when a route names a Forge app
  // or `delegatedCallers` is set, so a malformed header never affects other apps.
  forge(cfg)::
    requestAuthentication.new('app-forge-identity')
    + requestAuthentication.metadata.withLabels(h.labels(cfg))
    + requestAuthentication.spec.selector.withMatchLabels({ 'serving.knative.dev/service': 'app' })
    + requestAuthentication.spec.withJwtRules([
      requestAuthentication.spec.jwtRules.withAudiences([cfg.namespace])
      + requestAuthentication.spec.jwtRules.withForwardOriginalToken(false)
      + requestAuthentication.spec.jwtRules.withFromHeaders([{ name: 'x-forge-identity' }])
      + requestAuthentication.spec.jwtRules.withIssuer(cfg.forgeIdentity.issuer)
      + requestAuthentication.spec.jwtRules.withJwks(cfg.forgeIdentity.jwks)
      // Envoy removes a caller-sent x-forge-caller and sets it only from a verified pass.
      // With `delegatedCallers`, the forge-header-sanitizer EnvoyFilter also clears
      // all three headers first, so one stays absent when its claim is missing.
      // `forge_user_groups`, a list, is never mapped: the CSV claim carries it.
      + requestAuthentication.spec.jwtRules.withOutputClaimToHeaders(
        [{ header: 'x-forge-caller', claim: 'sub' }]
        + (if h.delegatedCallers(cfg) != [] then [
             { header: 'x-forge-user-email', claim: 'forge_user_email' },
             { header: 'x-forge-user-groups', claim: 'forge_user_groups_csv' },
           ] else [])
      ),
    ]),

  // Verifies the Okta ID token oauth2-proxy forwards as `Authorization: Bearer`.
  //
  // This only validates a token when one is present; it does not require one.
  // Requests are gated by the `app` AuthorizationPolicy, which matches on the
  // claims this produces. A forged or expired token is rejected outright.
  okta(cfg)::
    requestAuthentication.new('app-okta-jwt')
    + requestAuthentication.metadata.withLabels(h.labels(cfg))
    + requestAuthentication.spec.selector.withMatchLabels({ 'serving.knative.dev/service': 'app' })
    + requestAuthentication.spec.withJwtRules([
      requestAuthentication.spec.jwtRules.withForwardOriginalToken(false)
      + requestAuthentication.spec.jwtRules.withIssuer(cfg.oidc.issuer)
      + requestAuthentication.spec.jwtRules.withJwksUri(cfg.oidc.jwksUri),
    ]),
}
