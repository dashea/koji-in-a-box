# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM docker.io/library/fedora:36

# python-nss, a dependency of sigul, is missing from Fedora, hence the copr repo for that step
# python-yq is not packaged in Fedora
RUN dnf install --repo=fedora -y python3-robosignatory-0:0.7.0-5.fc36 \
                                 fedora-messaging-3.0.0-2.fc36 \
                                 dnf-plugins-core-4.1.0-1.fc36 \
                                 nss-tools-0:3.77.0-1.fc36 \
                                 gnupg2-0:2.3.4-2.fc36 \
                                 openssl-1:3.0.2-4.fc36 && \
    dnf -y copr enable dshea/buildsys && \
    dnf -y copr enable dshea/yq && \
    dnf -y install --repo=fedora,\*copr\* sigul-client-0:1.1^20220718gita6dc475-1.dshea4.fc36 \
                                          python3-yq-0:3.1.0-1.fc36 && \
    dnf clean all

COPY ./robosignatory.toml /etc/fedora-messaging/robosignatory.toml
COPY ./sigul.conf /etc/sigul/client.conf
COPY ./koji.conf /etc/koji.conf

# Add the public certificate and CA certificate
COPY ./robosignatory.crt /etc/pki/koji/robosignatory.crt
COPY ./koji_ca_cert.crt /etc/pki/koji/koji_ca_cert.crt
COPY ./package-signing-pub.key /etc/pki/koji/package-signing-pub.key

COPY ./robosignatory-entrypoint.sh /
ENTRYPOINT ["/robosignatory-entrypoint.sh"]
