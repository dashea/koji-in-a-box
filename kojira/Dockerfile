# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM docker.io/library/fedora:36

RUN dnf install --repo=fedora -y koji-utils-0:1.28.0-1.fc36 && \
    dnf clean all

# Change the kojira configuration to point to the koji-hub container
# kojira.pem will be created by the entrypoint
RUN sed -i -e 's|^server=.*|server = https://koji-hub/kojihub|' \
           -e 's|^;cert =.*|cert = /etc/pki/koji/kojira.pem|' \
           -e 's|^;serverca = .*|serverca = /etc/pki/koji/koji_ca_cert.crt|' \
           /etc/kojira/kojira.conf

# Add the public certificate and CA certificate
COPY ./kojira.crt /etc/pki/koji/kojira.crt
COPY ./koji_ca_cert.crt /etc/pki/koji/koji_ca_cert.crt

COPY ./kojira-entrypoint.sh /
ENTRYPOINT ["/kojira-entrypoint.sh"]
