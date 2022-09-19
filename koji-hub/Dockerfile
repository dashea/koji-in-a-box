# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM docker.io/library/fedora:36
EXPOSE 443

# Fedora docker images are built with tsflags=nodocs in dnf.conf.
# The koji-hub DDL is marked as a doc file, so disable this option when installing koji.
RUN dnf install --repo=fedora --setopt=tsflags= -y koji-0:1.28.0-1.fc36 && \
    dnf install --repo=fedora -y postgresql-0:14.1-3.fc36 \
                                 koji-hub-0:1.28.0-1.fc36 \
                                 mod_ssl-1:2.4.53-1.fc36 && \
    dnf clean all

# Create config changes that do not depends on runtime secrets
# /etc/httpd/conf.d/kojihub.conf: Configure for authentication via SSL certificates, add a ServerName
# /etc/httpd/conf.d/ssl.conf: Set the CA certificate and public certificate (private key is set in entrypoint using secret)
# /etc/koji-hub/hub.conf: Configure to look for username in certificate CN, add a ProxyDN to allow koji-web to connect
# /etc/koji.conf: Create a localhost profile for the koji CLI to be used by healthchecks (cert is set in entrypoint using secret)
#   NB: The ProxyDN settings must match the CN settings used to generated the certificates. See generate_secrets.conf.
#   The database secret will be added to koji-hub in the entrypoint in /etc/koji-hub/hub.conf.d/secret.conf
#   For the koji CLI, the cert file referenced in localhost.conf will be created by the entrypoint
RUN { \
        echo "<Location /kojihub/ssllogin>"; \
        echo "  SSLVerifyClient require"; \
        echo "  SSLVerifyDepth 10"; \
        echo "  SSLOptions +StdEnvVars"; \
        echo "</Location>"; \
        echo "ServerName koji-hub"; \
    } >> /etc/httpd/conf.d/kojihub.conf && \
    sed -i -e '/^SSLCertificateFile/d' \
           -e '/^SSLCertificateKeyFile/d' \
           /etc/httpd/conf.d/ssl.conf && \
    { \
        echo "SSLCertificateFile /etc/pki/koji/koji-hub.crt"; \
        echo "SSLCertificateChainFile /etc/pki/koji/koji_ca_cert.crt"; \
        echo "SSLCACertificateFile /etc/pki/koji/koji_ca_cert.crt"; \
    } >> /etc/httpd/conf.d/ssl.conf && \
    { \
        echo "DNUsernameComponent = CN"; \
        echo "ProxyDNs = CN=*,OU=koji-web,O=Koji in a Box,L=Boston,ST=Massachusetts,C=US"; \
    } >> /etc/koji-hub/hub.conf && \
    { \
        echo "[localhost]"; \
        echo "server = https://koji-hub/kojihub"; \
        echo "authtype = ssl"; \
        echo "cert = /etc/pki/koji/koji-hub.pem"; \
        echo "serverca = /etc/pki/koji/koji_ca_cert.crt"; \
    } >> /etc/koji.conf.d/localhost.conf

# Create the necessary filesystem skeleton under /mnt/koji
WORKDIR /mnt/koji
RUN mkdir packages repos work scratch repos-dist && \
    chown apache:apache packages repos work scratch repos-dist

# Add the public certificate and CA certificate
COPY ./koji-hub.crt /etc/pki/koji/koji-hub.crt
COPY ./koji_ca_cert.crt /etc/pki/koji/koji_ca_cert.crt

COPY ./koji-hub-entrypoint.sh /
ENTRYPOINT ["/koji-hub-entrypoint.sh"]
