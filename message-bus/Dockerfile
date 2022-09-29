# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM docker.io/library/fedora:36
EXPOSE 5671

RUN dnf install --repo=fedora -y rabbitmq-server-0:3.9.10-1.fc36.x86_64 && \
    dnf clean all

COPY ./rabbitmq.conf /etc/rabbitmq/rabbitmq.conf
COPY ./rabbitmq-definitions.json /etc/rabbitmq/definitions.json
COPY ./enabled_plugins /etc/rabbitmq/enabled_plugins

# Create a directory readable and writable by rabbitmq for the certificate key
# Needs to be writable so the key can be copied into it from the secret store at runtime
RUN mkdir /etc/pki/rabbitmq && \
    chown rabbitmq:rabbitmq /etc/pki/rabbitmq && \
    chmod 0700 /etc/pki/rabbitmq
COPY ./message-bus.crt /etc/pki/rabbitmq/
COPY ./koji_ca_cert.crt /etc/pki/rabbitmq/

COPY ./message-bus-entrypoint.sh /

USER rabbitmq:rabbitmq
VOLUME /var/lib/rabbitmq
ENTRYPOINT ["/message-bus-entrypoint.sh"]
