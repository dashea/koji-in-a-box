# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM docker.io/library/fedora:36
EXPOSE 44334
EXPOSE 44333

# sigul is effectively not available on Fedora, due to a combination of
# bitrot and python-nss being inexplicably missing, hence the COPR repo
RUN dnf -y install --repo=fedora dnf-plugins-core-4.1.0-1.fc36 \
                                 nss-tools-0:3.77.0-1.fc36 \
                                 openssl-1:3.0.2-4.fc36 && \
    dnf -y copr enable dshea/buildsys && \
    dnf -y install --repo=fedora,\*copr\* sigul-bridge-0:1.1^20220718gita6dc475-1.dshea4.fc36.noarch && \
    dnf clean all

COPY ./koji.conf /etc/koji.conf
COPY ./bridge.conf /etc/sigul/bridge.conf

# Add the public certificate and CA certificate
COPY ./sigul-bridge.crt /etc/pki/koji/sigul-bridge.crt
COPY ./koji_ca_cert.crt /etc/pki/koji/koji_ca_cert.crt

COPY ./sigul-bridge-entrypoint.sh /
ENTRYPOINT ["/sigul-bridge-entrypoint.sh"]
