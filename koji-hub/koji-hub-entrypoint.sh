#!/bin/sh -e

# REQUIRED ENVIRONMENT VARIABLES
# - POSTGRES_PASSWORD_FILE: path to a file containing the password for the koji user in postgres
# - KOJI_HUB_CERTIFICATE_KEY: path to a file containing the private key
if [ -z "$POSTGRES_PASSWORD_FILE" ]; then
    echo "\$POSTGRES_PASSWORD_FILE must be set"
    exit 1
fi
if [ ! -f "$POSTGRES_PASSWORD_FILE" ]; then
    echo "$POSTGRES_PASSWORD_FILE not present"
    exit 1
fi

if [ -z "$KOJI_HUB_CERTIFICATE_KEY" ]; then
    echo "\$KOJI_HUB_CERTIFICATE_KEY must be set"
    exit 1
fi
if [ ! -f "$KOJI_HUB_CERTIFICATE_KEY" ]; then
    echo "$KOJI_HUB_CERTIFICATE_KEY not present"
    exit 1
fi

PGPASSWORD="$(cat "$POSTGRES_PASSWORD_FILE")"
export PGPASSWORD

# Finish configuration:
# Create the key file referenced by /etc/httpd/conf.d/ssl.conf
cp "$KOJI_HUB_CERTIFICATE_KEY" /etc/pki/koji/koji-hub.key

# Create a configuration file containing the database password
touch /etc/koji-hub/hub.conf.d/secret.conf
chown root:apache /etc/koji-hub/hub.conf.d/secret.conf
chmod 0640 /etc/koji-hub/hub.conf.d/secret.conf
cat - >> /etc/koji-hub/hub.conf.d/secret.conf << EOF
[hub]
DBConnectionString = dbname=koji user=koji host=db port=5432 password=$PGPASSWORD
EOF

# Create the cert plus private key used by the localhost koji profile
cat /etc/pki/koji/koji-hub.crt "$KOJI_HUB_CERTIFICATE_KEY" > /etc/pki/koji/koji-hub.pem

# Initial db setup:
# Use the 'events' table to determine if the DB has been initialized already or not
psql -d koji -h db -p 5432 -U koji -c '\d events' > /dev/null 2>&1 ||
    psql -d koji -h db -p 5432 -U koji -f /usr/share/doc/koji/docs/schema.sql

# Create the admin user
psql -d koji -h db -p 5432 -U koji <<EOF
BEGIN;
INSERT INTO users (name, status, usertype) VALUES ('koji-admin', 0, 0) ON CONFLICT DO NOTHING;
INSERT INTO user_perms (user_id, perm_id, creator_id) (SELECT id, 1, id FROM users WHERE name = 'koji-admin') ON CONFLICT DO NOTHING;
COMMIT;
EOF

# Start httpd
exec /usr/sbin/httpd -DFOREGROUND
