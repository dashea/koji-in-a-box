#!/bin/sh -e

# REQUIRED ENVIRONMENT VARIABLES
# - KOJI_WEB_SECRET_FILE: path to a file containing the "Secret" setting for koji-web
# - KOJI_WEB_CERTIFICATE_KEY: path to a file containing the certificate private key
if [ -z "$KOJI_WEB_SECRET_FILE" ]; then
    echo "\$KOJI_WEB_SECRET_FILE must be set"
    exit 1
fi
if [ ! -f "$KOJI_WEB_SECRET_FILE" ]; then
    echo "$KOJI_WEB_SECRET_FILE not present"
    exit 1
fi

if [ -z "$KOJI_WEB_CERTIFICATE_KEY" ]; then
    echo "\$KOJI_WEB_CERTIFICATE_KEY must be set"
    exit 1
fi
if [ ! -f "$KOJI_WEB_CERTIFICATE_KEY" ]; then
    echo "$KOJI_WEB_CERTIFICATE_KEY not present"
    exit 1
fi

# Finish configuration:
# Create the certifcate file referenced in /etc/kojiweb/web.conf
cat /etc/pki/koji/koji-web.crt "$KOJI_WEB_CERTIFICATE_KEY" > /etc/pki/koji/koji-web.pem

# Add the key file configuration to httpd
echo "SSLCertificateKeyFile $KOJI_WEB_CERTIFICATE_KEY" >> /etc/httpd/conf.d/ssl.conf

# Set the secret
touch /etc/kojiweb/web.conf.d/secret.conf
chown root:apache /etc/kojiweb/web.conf.d/secret.conf
chmod 0640 /etc/kojiweb/web.conf.d/secret.conf
cat - >> /etc/kojiweb/web.conf.d/secret.conf << EOF
[web]
Secret = $(cat "$KOJI_WEB_SECRET_FILE")
EOF

# Start httpd
exec /usr/sbin/httpd -DFOREGROUND
