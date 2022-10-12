#!/usr/bin/python3
# Script to import a key into an offline sigul-server
#
# Copyright (C) 2022 David Shea  All rights reserved.
#
# This copyrighted material is made available to anyone wishing to use, modify,
# copy, or redistribute it subject to the terms and conditions of the GNU
# General Public License v.2.  This program is distributed in the hope that it
# will be useful, but WITHOUT ANY WARRANTY expressed or implied, including the
# implied warranties of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.  You should have
# received a copy of the GNU General Public License along with this program; if
# not, write to the Free Software Foundation, Inc., 51 Franklin Street, Fifth
# Floor, Boston, MA 02110-1301, USA.
#
# Author: David Shea <reallylongword@gmail.com>

import sys

sys.path.append("/usr/share/sigul")

from server import ServerConfiguration
import server_common
import utils


class AddKeyConfiguration(ServerConfiguration):
    def __init__(self, *args, **kwargs):
        super(AddKeyConfiguration, self).__init__(*args, **kwargs)
        self.batch_mode = True


# This is server.cmd_import_key, but skipping authentication and without the network request bits
def import_key(db, config, key_name, admin_name, import_key_passphrase, user_passphrase, key_file):
    # Check that the key doesn't exist yet
    if db.query(server_common.Key).filter_by(name=key_name).first() is not None:
        raise RuntimeError("Key %s already exists" % key_name)

    admin = db.query(server_common.User).filter_by(name=admin_name).first()
    if admin is None:
        raise RuntimeError("User %s not found" % admin_name)

    new_key_passphrase = utils.random_passphrase(config.passphrase_length)

    fingerprint = server_common.gpg_import_key(config, key_file)
    try:
        server_common.gpg_change_password(config, fingerprint, import_key_passphrase, new_key_passphrase)

        key = server_common.Key(key_name, server_common.KeyTypeEnum.gnupg.name, fingerprint)
        db.add(key)
        access = server_common.KeyAccess(key, admin, key_admin=True)
        access.set_passphrase(
            config, key_passphrase=new_key_passphrase, user_passphrase=user_passphrase, bind_params=None
        )
        db.add(access)
        db.commit()
    except:
        server_common.gpg_delete_key(config, fingerprint)
        raise


def main():
    parser = utils.create_basic_parser("Import a GPG key file", "/etc/sigul/server.conf")
    parser.add_option("--key-file", metavar="KEYFILE", help="Key to import")
    parser.add_option("--key-admin", metavar="USER", help="Initial key administrator")
    parser.add_option("--key-name", metavar="NAME", help="Key name")
    parser.add_option("--passphrase-file", metavar="PASSPHRASE_FILE", help="File containing the passphrase for KEYFILE")
    parser.add_option(
        "--new-key-passphrase-file", metavar="NEW_PASSPHRASE_FILE", help="File containing the new passphrase to use"
    )

    options = utils.optparse_parse_options_only(parser)

    if options.key_file is None:
        sys.exit("--key-file is required")
    if options.key_admin is None:
        sys.exit("--key-admin is required")
    if options.key_name is None:
        sys.exit("--key-name is required")

    if options.passphrase_file is None:
        passphrase = ""
    else:
        with open(options.passphrase_file, "rb") as f:
            passphrase = f.read()

    if options.new_key_passphrase_file is None:
        sys.exit("--new-key-passphrase-file is required")

    with open(options.new_key_passphrase_file, "rb") as f:
        new_key_passphrase = f.read()

    try:
        config = AddKeyConfiguration(options.config_file)
    except utils.ConfigurationError as e:
        sys.exit(str(e))

    utils.set_regid(config)
    utils.set_reuid(config)
    utils.update_HOME_for_uid(config)

    try:
        utils.nss_init(config)
    except utils.NSSInitError as e:
        sys.exit(str(e))

    db = server_common.db_open(config)
    with open(options.key_file, "rb") as key_file:
        import_key(db, config, options.key_name, options.key_admin, passphrase, new_key_passphrase, key_file)


if __name__ == "__main__":
    main()
