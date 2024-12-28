package com.keycloaktotraefik.logineventlistener.provider;

import org.keycloak.Config.Scope;
import org.keycloak.email.EmailTemplateProvider;
import org.keycloak.email.EmailTemplateProviderFactory;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;

public class CustomEmailTemplateProviderFactory implements EmailTemplateProviderFactory {

    @Override
    public EmailTemplateProvider create(KeycloakSession session) {
        return new CustomEmailTemplateProvider(session);
    }

    @Override
    public void init(Scope config) {
        // Nothing to initialize
    }

    @Override
    public void postInit(KeycloakSessionFactory factory) {
        // Nothing to post-initialize
    }

    @Override
    public void close() {
        // Nothing to close
    }

    @Override
    public String getId() {
        return "keycloak-to-traefik";
    }
}
