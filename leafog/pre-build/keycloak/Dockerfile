FROM quay.io/keycloak/keycloak:23.0.3 as builder


ENV KC_HTTP_RELATIVE_PATH=/auth
ENV KC_HEALTH_ENABLED=true
ENV KC_DB=postgres
ENV KC_FEATURES=token-exchange,admin2,account3,admin-fine-grained-authz

WORKDIR /opt/keycloak
# for demonstration purposes only, please make sure to use proper certificates in production instead
RUN /opt/keycloak/bin/kc.sh build --db postgres

FROM quay.io/keycloak/keycloak:23.0.3
COPY --from=builder /opt/keycloak/ /opt/keycloak/

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]