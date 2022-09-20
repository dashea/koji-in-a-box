ARG dockerarch
# hadolint ignore=DL3029
FROM --platform=$dockerarch docker.io/library/fedora:36

RUN dnf install --repo=fedora -y koji-builder-0:1.28.0-1.fc36 \
                                 koji-0:1.28.0-1.fc36 && \
    dnf clean all

COPY ./kojid.conf /etc/kojid/kojid.conf
COPY ./local-koji.conf /etc/koji.conf.d/local-koji.conf

# Add the public certificates and CA certificate
ARG arch
ENV ARCH=$arch
COPY ./koji-builder-$arch.crt /etc/pki/koji/koji-builder.crt
COPY ./koji-builder-probe.crt /etc/pki/koji/koji-builder-probe.crt
COPY ./koji_ca_cert.crt /etc/pki/koji/koji_ca_cert.crt

COPY ./koji-builder-entrypoint.sh /
ENTRYPOINT ["/koji-builder-entrypoint.sh"]
