# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM docker.io/library/fedora:36
EXPOSE 443

RUN dnf install --repo=fedora -y dist-git-0:1.16-6.fc36 \
                                 mod_ssl-1:2.4.53-1.fc36 && \
    dnf clean all

COPY ./ssl.conf /etc/httpd/conf.d/ssl.conf
COPY ./dist-git.conf /etc/dist-git/dist-git.conf

# Add the public certificate and CA certificate
COPY ./dist-git.crt /etc/pki/koji/dist-git.crt
COPY ./koji_ca_cert.crt /etc/pki/koji/koji_ca_cert.crt

COPY ./dist-git-entrypoint.sh /

VOLUME /var/lib/dist-git/git
VOLUME /var/lib/dist-git/cache/lookaside/pkgs
ENTRYPOINT ["/dist-git-entrypoint.sh"]
