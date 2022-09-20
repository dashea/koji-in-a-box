# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM docker.io/library/fedora:36
EXPOSE 443

RUN dnf install --repo=fedora -y koji-web-0:1.28.0-1.fc36 \
                                 mod_ssl-1:2.4.53-1.fc36 && \
    dnf clean all

# Set up config files
COPY ./kojiweb-login.conf /etc/httpd/conf.d/kojiweb-login.conf
COPY ./kojiweb-servername.conf /etc/httpd/conf.d/kojiweb-servername.conf
COPY ./ssl.conf /etc/httpd/conf.d/ssl.conf
COPY ./koji-web.conf /etc/kojiweb/web.conf

# Add the public certificate and CA certificate
COPY ./koji-web.crt /etc/pki/koji/koji-web.crt
COPY ./koji_ca_cert.crt /etc/pki/koji/koji_ca_cert.crt

COPY ./koji-web-entrypoint.sh /
ENTRYPOINT ["/koji-web-entrypoint.sh"]
