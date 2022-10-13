#!/bin/sh -e

# REQUIRED ENVIRONMENT VARIABLES
# - POSTGRES_PASSWORD_FILE: path to a file containing the password for the koji user in postgres
# - KOJI_HUB_CERTIFICATE_KEY: path to a file containing the private key
# OPTIONAL ENVIRONMENT VARIABLES
# - KOJI_BUILDERS: space-separated list of builder names (will be created as koji-builder-<builder>
# - KOJI_BUILDER_<builder-name>: List of architectures for given builder
# The first listed builder is also added to the createrepo channel
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

# Create the initial set of users
for user in koji-admin koji-hub koji-user sigul-client kojira ; do
    psql -d koji -h db -p 5432 -U koji -v user="$user" <<EOF
INSERT INTO users (name, status, usertype) VALUES (:'user', 0, 0) ON CONFLICT DO NOTHING;
EOF
done

# Add admin permission to koji-admin
psql -d koji -h db -p 5432 -U koji <<EOF
INSERT INTO user_perms (user_id, perm_id, creator_id)
  (SELECT admin_user.id, admin_perm.id, admin_user.id
   FROM (SELECT id FROM users WHERE name = 'koji-admin') AS admin_user,
        (SELECT id FROM permissions WHERE name = 'admin') AS admin_perm)
  ON CONFLICT DO NOTHING;
EOF

# Add repo permission to kojira
psql -d koji -h db -p 5432 -U koji <<EOF
INSERT INTO user_perms (user_id, perm_id, creator_id)
    (SELECT kojira_user.id, repo_perm.id, admin_user.id
     FROM (SELECT id FROM users WHERE name = 'kojira') AS kojira_user,
          (SELECT id FROM permissions WHERE name = 'repo') AS repo_perm,
          (SELECT id FROM users WHERE name = 'koji-admin') AS admin_user)
    ON CONFLICT DO NOTHING;
EOF

# Add sign permissions to sigul-client
psql -d koji -h db -p 5432 -U koji <<EOF
INSERT INTO user_perms (user_id, perm_id, creator_id)
    (SELECT sigul_client.id, sign_perm.id, admin_user.id
     FROM (SELECT id FROM users WHERE name = 'sigul-client') AS sigul_client,
          (SELECT id FROM permissions WHERE name = 'sign') AS sign_perm,
          (SELECT id FROM users WHERE name = 'koji-admin') AS admin_user)
    ON CONFLICT DO NOTHING;
EOF

# Create the builders
firstbuilder=1
for builder_arch in $KOJI_BUILDERS ; do
    eval "archlist=\$KOJI_BUILDER_${builder_arch}"
    hostname="koji-builder-${builder_arch}"

    # shellcheck disable=SC2154,SC2086
    psql -d koji -h db -p 5432 -U koji -v buildername="$hostname" -v builderarches="$archlist" <<EOF
BEGIN;
INSERT INTO users (name, status, usertype) VALUES (:'buildername', 0, 1) ON CONFLICT DO NOTHING;
INSERT INTO host (user_id, name)
   (SELECT id, name FROM users WHERE name = :'buildername')
   ON CONFLICT DO NOTHING;
INSERT INTO host_config (host_id, arches, creator_id)
   (SELECT builder_host.id, :'builderarches', admin_user.id
    FROM (SELECT id FROM host WHERE name = :'buildername') AS builder_host,
         (SELECT id FROM users WHERE name = 'koji-admin') AS admin_user)
   ON CONFLICT DO NOTHING;
INSERT INTO host_channels (host_id, channel_id, creator_id)
   (SELECT builder_host.id, default_channel.id, admin_user.id
    FROM (SELECT id FROM host WHERE name = :'buildername') AS builder_host,
         (SELECT id FROM channels WHERE name = 'default') AS default_channel,
         (SELECT id FROM users WHERE name = 'koji-admin') AS admin_user)
   ON CONFLICT DO NOTHING;
END;
EOF

    if [ "$firstbuilder" -eq 1 ]; then
        firstbuilder=0
        psql -d koji -h db -p 5432 -U koji -v buildername="$hostname" << EOF
INSERT INTO host_channels (host_id, channel_id, creator_id)
   (SELECT builder_host.id, default_channel.id, admin_user.id
    FROM (SELECT id FROM host WHERE name = :'buildername') AS builder_host,
         (SELECT id FROM channels WHERE name = 'createrepo') AS default_channel,
         (SELECT id FROM users WHERE name = 'koji-admin') AS admin_user)
   ON CONFLICT DO NOTHING;
EOF
    fi
done

# Start httpd
exec /usr/sbin/httpd -DFOREGROUND
