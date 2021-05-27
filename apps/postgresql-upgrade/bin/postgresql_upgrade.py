#!/usr/bin/env python3

"""
PostgreSQL upgrade script.

Usage:

docker run -it \
    -v ~/Downloads/postgres_11_vol/:/var/lib/postgresql/ \
    gcr.io/mcback/postgresql-upgrade \
    postgresql_upgrade.py --old_version=11 --new_version=12 [--[no-]vacuum]
"""

import argparse
import getpass
import glob
import logging
import multiprocessing
import os
import pathlib
import shutil
import signal
import socket
import subprocess
import time

logging.basicConfig(level=logging.DEBUG)


class PostgresUpgradeError(Exception):
    pass


def _tcp_port_is_open(port: int, hostname: str = 'localhost') -> bool:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    try:
        result = sock.connect_ex((hostname, port))
    except socket.gaierror as ex:
        logging.warning(f"Unable to resolve {hostname}: {ex}")
        return False

    if result == 0:
        try:
            sock.shutdown(socket.SHUT_RDWR)
        except OSError as ex:
            # Quiet down "OSError: [Errno 57] Socket is not connected"
            logging.warning(f"Error while shutting down socket: {ex}")

    sock.close()
    return result == 0


def _dir_exists_and_accessible(directory: str) -> bool:
    return os.path.isdir(directory) and os.access(directory, os.X_OK)


def postgres_upgrade(old_version: int, new_version: int, vacuum: bool = True):
    logging.debug(f"Old version: {old_version}; new version: {new_version}; VACUUM: {vacuum}")

    postgres_data_dir = "/var/lib/postgresql"

    if not _dir_exists_and_accessible(postgres_data_dir):
        raise PostgresUpgradeError(f"{postgres_data_dir} does not exist or is inaccessible.")

    if getpass.getuser() != 'postgres':
        raise PostgresUpgradeError("This script is to be run as 'postgres' user.")

    if new_version <= old_version:
        raise PostgresUpgradeError(f"New version {new_version} is not newer than old version {old_version}.")

    # TODO: we can do multiple major versions at once
    if new_version - old_version != 1:
        raise PostgresUpgradeError(f"New version {new_version} is not only one major version newer than {old_version}")

    old_data_dir = os.path.join(postgres_data_dir, str(old_version))
    new_data_dir = os.path.join(postgres_data_dir, str(new_version))

    if not _dir_exists_and_accessible(old_data_dir):
        raise PostgresUpgradeError((
            f"Old data directory {old_data_dir} does not exist or is inaccessible; forgot to mount it?"
        ))

    if os.path.exists(new_data_dir):
        raise PostgresUpgradeError((
            f"New data directory {new_data_dir} already exists; if the previous attempt to upgrade failed, run "
            "something like this:\n\n"
            f"    rm -rf {new_data_dir}\n"
            "\n\n"
            "on a container, or adjust the path on the host."
        ))

    old_main_dir = os.path.join(old_data_dir, "main")
    new_main_dir = os.path.join(new_data_dir, "main")

    if not _dir_exists_and_accessible(old_main_dir):
        raise PostgresUpgradeError(f"Old main directory {old_main_dir} does not exist or is inaccessible.")

    old_pg_version_path = os.path.join(old_main_dir, 'PG_VERSION')
    if not os.path.isfile(old_pg_version_path):
        raise PostgresUpgradeError(f"{old_pg_version_path} does not exist or is inaccessible.")

    old_postmaster_pid_path = os.path.join(old_main_dir, 'postmaster.pid')
    if os.path.exists(old_postmaster_pid_path):
        raise PostgresUpgradeError(f"{old_postmaster_pid_path} exists; is the database running?")

    # Create run directories
    for version in [old_version, new_version]:
        pathlib.Path(f"/var/run/postgresql/{version}-main.pg_stat_tmp/").mkdir(parents=True, exist_ok=True)

    # Remove cruft that might have been left over from last attempt to do the upgrade
    patterns = [
        'pg_*.log',
        'pg_*.custom',
        'pg_upgrade_dump_globals.sql',
    ]
    for pattern in patterns:
        for file in glob.glob(os.path.join(postgres_data_dir, pattern)):
            logging.debug(f"Deleting {file}...")
            os.unlink(pattern)

    old_bin_dir = f"/usr/lib/postgresql/{old_version}/bin/"
    new_bin_dir = f"/usr/lib/postgresql/{new_version}/bin/"

    if not _dir_exists_and_accessible(old_bin_dir):
        raise PostgresUpgradeError(f"Old binaries directory {old_bin_dir} does not exist or is inaccessible.")
    if not _dir_exists_and_accessible(new_bin_dir):
        raise PostgresUpgradeError(f"New binaries directory {new_bin_dir} does not exist or is inaccessible.")

    new_initdb = os.path.join(new_bin_dir, 'initdb')
    if not os.access(new_initdb, os.X_OK):
        raise PostgresUpgradeError(f"New 'initdb' at {new_initdb} does not exist.")

    new_pg_upgrade = os.path.join(new_bin_dir, 'pg_upgrade')
    if not os.access(new_pg_upgrade, os.X_OK):
        raise PostgresUpgradeError(f"New 'pg_upgrade' at {new_pg_upgrade} does not exist.")

    new_vacuumdb = os.path.join(new_bin_dir, 'vacuumdb')
    if not os.access(new_vacuumdb, os.X_OK):
        raise PostgresUpgradeError(f"New 'vacuumdb' at {new_vacuumdb} does not exist.")

    new_postgres = os.path.join(new_bin_dir, 'postgres')
    if not os.access(new_postgres, os.X_OK):
        raise PostgresUpgradeError(f"New 'postgres' at {new_postgres} does not exist.")

    old_port = 50432
    new_port = 50433

    logging.info("Updating memory configuration...")
    subprocess.check_call(['/opt/postgresql-base/bin/update_memory_config.sh'])

    old_tmp_conf_dir = f"/var/tmp/postgresql/conf/{old_version}"
    new_tmp_conf_dir = f"/var/tmp/postgresql/conf/{new_version}"

    if os.path.exists(old_tmp_conf_dir):
        logging.debug(f"Removing {old_tmp_conf_dir}...")
        shutil.rmtree(old_tmp_conf_dir)
    if os.path.exists(new_tmp_conf_dir):
        logging.debug(f"Removing {new_tmp_conf_dir}...")
        shutil.rmtree(new_tmp_conf_dir)

    logging.info("Creating temporary configurations for both instances...")
    conf_list = os.listdir('/etc/postgresql/')
    if len(conf_list) != 1:
        raise PostgresUpgradeError(f"More / less than one PostgreSQL configuration set has been found: {conf_list}")
    current_version = conf_list[0]
    if not current_version.isdecimal():
        raise PostgresUpgradeError(f"Invalid PostgreSQL version: {current_version}")
    current_version = int(current_version)

    current_postgresql_config_path = os.path.join('/etc/postgresql/', str(current_version), 'main')
    if not os.path.isfile(os.path.join(current_postgresql_config_path, 'postgresql.conf')):
        raise PostgresUpgradeError(f"postgresql.conf does not exist in {current_postgresql_config_path}.")

    shutil.copytree(current_postgresql_config_path, old_tmp_conf_dir)
    shutil.copytree(current_postgresql_config_path, new_tmp_conf_dir)

    ram_size = int(subprocess.check_output(['/container_memory_limit.sh']).decode('utf-8'))
    assert ram_size, "RAM size can't be zero."
    new_maintenance_work_mem = int(ram_size / 10)
    logging.info(f"New maintenance work memory limit: {new_maintenance_work_mem} MB")

    for tmp_conf_dir, port, version, extra_config in [
        (old_tmp_conf_dir, old_port, old_version, '',),
        (new_tmp_conf_dir, new_port, new_version, f'maintenance_work_mem = {new_maintenance_work_mem}MB',),
    ]:
        with open(os.path.join(tmp_conf_dir, 'postgresql.conf'), 'a') as postgresql_conf:
            postgresql_conf.write(f"""
            
            port = {port}
            data_directory = '/var/lib/postgresql/{version}/main'
            hba_file = '{tmp_conf_dir}/pg_hba.conf'
            ident_file = '{tmp_conf_dir}/pg_ident.conf'
            external_pid_file = '/var/run/postgresql/{version}-main.pid'
            cluster_name = '{version}/main'
            stats_temp_directory = '/var/run/postgresql/{version}-main.pg_stat_tmp'
            
            {extra_config}
    
            """)

    logging.info("Running initdb...")
    pathlib.Path(new_main_dir).mkdir(parents=True, exist_ok=True)
    subprocess.check_call([
        new_initdb,
        '--pgdata', new_main_dir,
        '--data-checksums',
        '--encoding', 'UTF-8',
        '--lc-collate', 'en_US.UTF-8',
        '--lc-ctype', 'en_US.UTF-8',
    ])

    upgrade_command = [
        new_pg_upgrade,
        '--jobs', str(multiprocessing.cpu_count()),
        '--old-bindir', old_bin_dir,
        '--new-bindir', new_bin_dir,
        '--old-datadir', old_main_dir,
        '--new-datadir', new_main_dir,
        '--old-port', str(old_port),
        '--new-port', str(new_port),
        '--old-options', f" -c config_file={old_tmp_conf_dir}/postgresql.conf",
        '--new-options', f" -c config_file={new_tmp_conf_dir}/postgresql.conf",
        '--link',
        '--verbose',
    ]

    logging.info("Testing if clusters are compatible...")
    subprocess.check_call(upgrade_command + ['--check'], cwd=postgres_data_dir)

    logging.info("Upgrading...")
    subprocess.check_call(upgrade_command, cwd=postgres_data_dir)

    logging.info("Cleaning up old data directory...")
    shutil.rmtree(old_data_dir)

    logging.info("Cleaning up scripts...")
    for script in [
        'analyze_new_cluster.sh',
        'delete_old_cluster.sh',
        'pg_upgrade_internal.log',
        'pg_upgrade_server.log',
        'pg_upgrade_utility.log',
    ]:
        script_path = os.path.join(postgres_data_dir, script)
        if os.path.isfile(script_path):
            os.unlink(script_path)

    if vacuum:

        logging.info("Starting PostgreSQL to run VACUUM ANALYZE...")
        postgres_proc = subprocess.Popen([
            new_postgres,
            '-D', new_main_dir,
            '-c', f'config_file={new_tmp_conf_dir}/postgresql.conf',
        ])

        while not _tcp_port_is_open(port=new_port):
            logging.info("Waiting for PostgreSQL to come up...")
            time.sleep(1)

        logging.info("Running VACUUM ANALYZE...")
        logging.info("(monitor locks while running that because PostgreSQL might decide to do autovacuum!)")
        subprocess.check_call([
            new_vacuumdb,
            '--port', str(new_port),
            '--all',
            '--verbose',
            '--jobs', str(multiprocessing.cpu_count()),
            # No --analyze-in-stages because we're ready to wait for the full statistics
        ])

        logging.info("Waiting for PostgreSQL to shut down...")
        postgres_proc.send_signal(signal.SIGTERM)
        postgres_proc.wait()

    else:
        logging.info("Skipping VACUUM ANALYZE...")

    logging.info("Done!")


def main():
    parser = argparse.ArgumentParser(description="Upgrade PostgreSQL dataset.")
    parser.add_argument("-o", "--old_version", type=int, required=True,
                        help="Version to upgrade from")
    parser.add_argument("-n", "--new_version", type=int, required=True,
                        help="Version to upgrade to")

    # Replace with BooleanOptionalAction after Python 3.9 upgrade
    vacuum_group = parser.add_mutually_exclusive_group(required=False)
    vacuum_group.add_argument('--vacuum', dest='vacuum', action='store_true',
                              help="VACUUM ANALYZE the upgraded cluster")
    vacuum_group.add_argument('--no-vacuum', dest='vacuum', action='store_false',
                              help="Do not VACUUM ANALYZE the upgraded cluster")
    parser.set_defaults(vacuum=True)

    args = parser.parse_args()

    postgres_upgrade(old_version=args.old_version, new_version=args.new_version, vacuum=args.vacuum)


if __name__ == '__main__':
    main()
