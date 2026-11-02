// Istio RequestAuthentications: verification of the Okta ID token.
local h = import 'helpers.libsonnet';
local requestAuthentication = (import 'libs.libsonnet').istio.security.v1.requestAuthentication;

{
  // Verifies the pass an identity service signs for each Forge request, one rule
  // per issuer in `forgeIdentity.issuers`. The audience pins a pass to this app.
  // Rendered only when a route names a Forge app or `delegatedCallers` is set, so
  // a malformed header never affects other apps.
  forge(cfg)::
    requestAuthentication.new('app-forge-identity')
    + requestAuthentication.metadata.withLabels(h.labels(cfg))
    + requestAuthentication.spec.selector.withMatchLabels({ 'serving.knative.dev/service': 'app' })
    + requestAuthentication.spec.withJwtRules([
      requestAuthentication.spec.jwtRules.withAudiences([cfg.namespace])
      + requestAuthentication.spec.jwtRules.withForwardOriginalToken(false)
      + requestAuthentication.spec.jwtRules.withFromHeaders([{ name: 'x-forge-identity' }])
      + requestAuthentication.spec.jwtRules.withIssuer(cfg.forgeIdentity.issuers[prefix].issuer)
      + requestAuthentication.spec.jwtRules.withJwks(cfg.forgeIdentity.issuers[prefix].jwks)
      // Envoy removes a caller-sent x-forge-caller and sets it only from a verified pass.
      // `x-forge-issuer` tells apart callers with the same name under different prefixes.
      // `x-forge-app` and `x-forge-environment` name the caller's app and its environment
      // apart, where `sub` packs both (`<repo>`, `<repo>-prod`); a pass from a binding
      // stamped before them has neither, so the Forge VirtualService always clears a
      // caller-sent copy first.
      // With `delegatedCallers`, the forge-header-sanitizer EnvoyFilter also clears
      // these headers first, so one stays absent when its claim is missing.
      // `forge_user_groups`, a list, is never mapped: the CSV claim carries it.
      + requestAuthentication.spec.jwtRules.withOutputClaimToHeaders(
        [
          { header: 'x-forge-caller', claim: 'sub' },
          { header: 'x-forge-issuer', claim: 'iss' },
          { header: 'x-forge-app', claim: 'forge_app' },
          { header: 'x-forge-environment', claim: 'forge_environment' },
        ]
        + (if h.delegatedCallers(cfg) != [] then [
             { header: 'x-forge-user-email', claim: 'forge_user_email' },
             { header: 'x-forge-user-groups', claim: 'forge_user_groups_csv' },
           ] else [])
      )
      for prefix in std.objectFields(cfg.forgeIdentity.issuers)
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
