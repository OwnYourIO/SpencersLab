package com.keycloaktotraefik.logineventlistener.provider;

import org.keycloak.email.freemarker.FreeMarkerEmailTemplateProvider;
import org.keycloak.models.KeycloakSession;

public class CustomEmailTemplateProvider extends FreeMarkerEmailTemplateProvider {
    // Really all this is doing is making the new-ip-login.ftl file available for
    // use.
    public CustomEmailTemplateProvider(KeycloakSession session) {
        super(session);
    }
}