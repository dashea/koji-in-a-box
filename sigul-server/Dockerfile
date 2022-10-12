# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM docker.io/library/fedora:36

# sigul is effectively not available on Fedora, due to a combination of
# bitrot and python-nss being inexplicably missing, hence the COPR repo
RUN dnf -y install --repo=fedora dnf-plugins-core-4.1.0-1.fc36 \
                                 nss-tools-0:3.77.0-1.fc36 \
                                 openssl-1:3.0.2-4.fc36 && \
    dnf -y copr enable dshea/buildsys && \
    dnf -y install --repo=fedora,\*copr\* sigul-server-0:1.1^20220718gita6dc475-1.dshea4.fc36.noarch && \
    dnf clean all

COPY ./server.conf /etc/sigul/server.conf

# Add the public certificate and CA certificate
COPY ./sigul-server.crt /etc/pki/koji/sigul-server.crt
COPY ./koji_ca_cert.crt /etc/pki/koji/koji_ca_cert.crt

COPY ./server_add_key.py /

COPY ./sigul-server-entrypoint.sh /
ENTRYPOINT ["/sigul-server-entrypoint.sh"]
