# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM docker.io/library/fedora:36
EXPOSE 443

RUN dnf install --repo=fedora -y koji-web-0:1.28.0-1.fc36 \
                                 mod_ssl-1:2.4.53-1.fc36 && \
    dnf clean all

# Set up config files:
# /etc/httpd/conf.d/kojiweb.conf: Use SSL for login
# /etc/httpd/conf.d/ssl.conf: Set the certificate files (private key will be set up in the entrypoint), set up a reverse proxy to koji-hub
# /etc/httpd/conf/httpd.conf: Set a server name
# /etc/kojiweb/web.conf: Set the URLs of the koji-hub and certificate paths (combined cert and private key will be created in entrypoint, Secret will be set in entrypoint)
RUN { \
        echo "<Location /koji/login>"; \
        echo "  SSLVerifyClient require"; \
        echo "  SSLVerifyDepth 10"; \
        echo "  SSLOptions +StdEnvVars"; \
        echo "</Location>"; \
    } >> /etc/httpd/conf.d/kojiweb.conf && \
    sed -i -e '/^SSLCertificateFile/d' \
           -e '/^SSLCertificateKeyFile/d' \
           /etc/httpd/conf.d/ssl.conf && \
    { \
        echo "SSLCertificateFile /etc/pki/koji/koji-web.crt"; \
        echo "SSLCertificateChainFile /etc/pki/koji/koji_ca_cert.crt"; \
        echo "SSLCACertificateFile /etc/pki/koji/koji_ca_cert.crt"; \
        echo "SSLProxyEngine on"; \
        echo "SSLProxyCACertificateFile /etc/pki/koji/koji_ca_cert.crt"; \
        echo "SSLProxyMachineCertificateFile /etc/pki/koji/koji-web.pem"; \
        echo "ProxyPass /kojihub https://koji-hub/kojihub"; \
        echo "ProxyPass /kojifiles https://koji-hub/kojifiles"; \
        echo "ProxyPassReverse /kojihub https://koji-hub/kojihub"; \
        echo "ProxyPassReverse /kojifiles https://koji-hub/kojifiles"; \
    } >> /etc/httpd/conf.d/ssl.conf && \
    echo "ServerName koji-web" >> /etc/httpd/conf/httpd.conf && \
    sed -i -e 's|^KojiHubURL = .*|KojiHubURL = https://koji-hub/kojihub|' \
           -e 's|^KojiFilesURL = .*|KojiFilesURL = /kojifiles|' \
           -e 's|^# KojiHubCA = .*|KojiHubCA = /etc/pki/koji/koji_ca_cert.crt|' \
           -e 's|^# WebAuthType = .*|WebAuthType = ssl|' \
           -e 's|^# WebCert = .*|WebCert = /etc/pki/koji/koji-web.pem|' \
           /etc/kojiweb/web.conf

# Add the public certificate and CA certificate
COPY ./koji-web.crt /etc/pki/koji/koji-web.crt
COPY ./koji_ca_cert.crt /etc/pki/koji/koji_ca_cert.crt

COPY ./koji-web-entrypoint.sh /
ENTRYPOINT ["/koji-web-entrypoint.sh"]
