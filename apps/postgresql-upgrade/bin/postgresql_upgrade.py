#!/usr/bin/env python3

"""
PostgreSQL upgrade script.

Usage:

time docker run -it \
    --shm-size=64g \
    -v ~/Downloads/postgres_11_vol/:/var/lib/postgresql/ \
    gcr.io/mcback/postgresql-upgrade \
    postgresql_upgrade.py --source_version=11 --target_version=12 \
    > postgresql_upgrade.log
"""

import argparse
import dataclasses
import getpass
import glob
import logging
import multiprocessing
import os
import pathlib
import shutil
import signal
import subprocess
import time

logging.basicConfig(level=logging.DEBUG)


class PostgresUpgradeError(Exception):
    pass


POSTGRES_DATA_DIR = "/var/lib/postgresql"
POSTGRES_USER = 'postgres'


def _dir_exists_and_accessible(directory: str) -> bool:
    return os.path.isdir(directory) and os.access(directory, os.X_OK)


def _ram_size_mb() -> int:
    """Return RAM size (in megabytes) that is allocated to the container."""
    ram_size = int(subprocess.check_output(['/container_memory_limit.sh']).decode('utf-8'))
    assert ram_size, "RAM size can't be zero."
    return ram_size


class _PostgresVersion(object):
    """
    Data object of a single PostgreSQL version to upgrade from / to.
    """
    __slots__ = [
        'version',
        'data_dir',
        'main_dir',
        'bin_dir',
        'initdb',
        'pg_upgrade',
        'vacuumdb',
        'postgres',
        'tmp_conf_dir',
        'port',
    ]

    @classmethod
    def _current_postgresql_config_path(cls) -> str:
        """
        Returns path to currently present PostgreSQL configuration directory.

        :return: Path to currently present PostgreSQL configuration directory, e.g. /etc/postgresql/11/main/.
        """
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

        return current_postgresql_config_path

    def __init__(self,
                 version: int,
                 target_version: bool,
                 starting_version: bool,
                 port: int,
                 extra_postgres_config: str):
        """
        Constructor.

        Checks whether various binaries / paths / directories are available.

        :param version: PostgreSQL version number, e.g. 11.
        :param target_version: If True, this data object represents a version that is being upgraded *to*.
        :param starting_version: If True, this data object represents a source version, i.e. the initial version that is
        being upgraded from.
        :param port: PostgreSQL temporary port number, e.g. 50432.
        :param extra_postgres_config: Extra lines to add to temporary postgresql.conf.
        """
        assert isinstance(version, int), "Version number must be integer."
        self.version = version
        assert isinstance(port, int), "Port must be an integer."
        self.port = port

        self.data_dir = os.path.join(POSTGRES_DATA_DIR, str(version))
        if target_version:
            if os.path.exists(self.data_dir):
                raise PostgresUpgradeError((
                    f"New data directory {self.data_dir} already exists; if the previous attempt to upgrade failed, "
                    "run something like this:\n\n"
                    f"    rm -rf {self.data_dir}\n"
                    "\n\n"
                    "on a container, or adjust the path on the host, or revert to old ZFS snapshot."
                ))
        else:
            if starting_version:
                if not _dir_exists_and_accessible(self.data_dir):
                    raise PostgresUpgradeError((
                        f"Old data directory {self.data_dir} does not exist or is inaccessible; forgot to mount it?"
                    ))

        self.main_dir = os.path.join(self.data_dir, "main")
        if not target_version:
            if starting_version:
                if not _dir_exists_and_accessible(self.main_dir):
                    raise PostgresUpgradeError(f"Old main directory {self.main_dir} does not exist or is inaccessible.")

                pg_version_path = os.path.join(self.main_dir, 'PG_VERSION')
                if not os.path.isfile(pg_version_path):
                    raise PostgresUpgradeError(f"{pg_version_path} does not exist or is inaccessible.")

                postmaster_pid_path = os.path.join(self.main_dir, 'postmaster.pid')
                if os.path.exists(postmaster_pid_path):
                    raise PostgresUpgradeError(f"{postmaster_pid_path} exists; is the database running?")

        # Create run directory
        pathlib.Path(f"/var/run/postgresql/{version}-main.pg_stat_tmp/").mkdir(parents=True, exist_ok=True)

        self.bin_dir = f"/usr/lib/postgresql/{version}/bin/"

        if not _dir_exists_and_accessible(self.bin_dir):
            raise PostgresUpgradeError(f"Binaries directory {self.bin_dir} does not exist or is inaccessible.")
        if not _dir_exists_and_accessible(self.bin_dir):
            raise PostgresUpgradeError(f"Binaries directory {self.bin_dir} does not exist or is inaccessible.")

        self.postgres = os.path.join(self.bin_dir, 'postgres')
        if not os.access(self.postgres, os.X_OK):
            raise PostgresUpgradeError(f"'postgres' at {self.postgres} does not exist.")

        if target_version:

            self.initdb = os.path.join(self.bin_dir, 'initdb')
            if not os.access(self.initdb, os.X_OK):
                raise PostgresUpgradeError(f"'initdb' at {self.initdb} does not exist.")

            self.pg_upgrade = os.path.join(self.bin_dir, 'pg_upgrade')
            if not os.access(self.pg_upgrade, os.X_OK):
                raise PostgresUpgradeError(f"'pg_upgrade' at {self.pg_upgrade} does not exist.")

            self.vacuumdb = os.path.join(self.bin_dir, 'vacuumdb')
            if not os.access(self.vacuumdb, os.X_OK):
                raise PostgresUpgradeError(f"'vacuumdb' at {self.vacuumdb} does not exist.")

        logging.info(f"Creating temporary configuration for version {version}...")
        self.tmp_conf_dir = f"/var/tmp/postgresql/conf/{version}"
        if os.path.exists(self.tmp_conf_dir):
            shutil.rmtree(self.tmp_conf_dir)
        current_postgresql_config_path = self._current_postgresql_config_path()
        shutil.copytree(current_postgresql_config_path, self.tmp_conf_dir)

        with open(os.path.join(self.tmp_conf_dir, 'postgresql.conf'), 'a') as postgresql_conf:
            postgresql_conf.write(f"""

            port = {port}
            data_directory = '/var/lib/postgresql/{version}/main'
            hba_file = '{self.tmp_conf_dir}/pg_hba.conf'
            ident_file = '{self.tmp_conf_dir}/pg_ident.conf'
            external_pid_file = '/var/run/postgresql/{version}-main.pid'
            cluster_name = '{version}/main'
            stats_temp_directory = '/var/run/postgresql/{version}-main.pg_stat_tmp'

            {extra_postgres_config}

            """)


@dataclasses.dataclass
class _PostgresVersionPair(object):
    """
    Version pair to upgrade between.

    Must be different by exactly one version number, e.g. 11 and 12.
    """
    old_version: _PostgresVersion
    new_version: _PostgresVersion


class _PostgreSQLServer(object):
    """PostgreSQL server helper."""

    __slots__ = [
        '__port',
        '__bin_dir',
        '__data_dir',
        '__conf_dir',

        '__proc',
    ]

    def __init__(self, port: int, bin_dir: str, data_dir: str, conf_dir: str):
        assert isinstance(port, int), "Port must be an integer."
        assert os.path.isdir(bin_dir), f"{bin_dir} does not exist."
        assert os.access(os.path.join(bin_dir, 'postgres'), os.X_OK), f"'postgres' does not exist in {bin_dir}."
        assert os.access(os.path.join(bin_dir, 'pg_isready'), os.X_OK), f"'pg_isready' does not exist in {bin_dir}."
        assert os.path.isdir(data_dir), f"{data_dir} does not exist."
        assert os.path.isdir(conf_dir), f"{conf_dir} does not exist."
        assert os.path.isfile(
            os.path.join(conf_dir, 'postgresql.conf')
        ), f"postgresql.conf in {conf_dir} does not exist."

        self.__bin_dir = bin_dir
        self.__port = port
        self.__data_dir = data_dir
        self.__conf_dir = conf_dir

        self.__proc = None

    def start(self) -> None:
        assert not self.__proc, "PostgreSQL is already started."

        logging.info("Starting PostgreSQL...")
        self.__proc = subprocess.Popen([
            os.path.join(self.__bin_dir, 'postgres'),
            '-D', self.__data_dir,
            '-c', f'config_file={self.__conf_dir}/postgresql.conf',
        ])

        # Waiting for port is not enough as PostgreSQL might be recovering
        while True:
            try:
                subprocess.check_call([os.path.join(self.__bin_dir, 'pg_isready'), '--port', str(self.__port)])
            except subprocess.CalledProcessError as ex:
                logging.debug(f"pg_isready failed: {ex}")
                logging.info("Waiting for PostgreSQL to come up...")
                time.sleep(1)
            else:
                break

        logging.info("PostgreSQL is up!")

    def stop(self) -> None:
        assert self.__proc, "PostgreSQL has not been started."

        logging.info("Waiting for PostgreSQL to shut down...")
        self.__proc.send_signal(signal.SIGTERM)
        self.__proc.wait()

        logging.info("PostgreSQL has been shut down")

        self.__proc = None


def postgres_upgrade(source_version: int, target_version: int) -> None:
    """
    Upgrade PostgreSQL from source version up to target version.

    :param source_version: Source dataset version, e.g. 11.
    :param target_version: Target dataset version, e.g. 13.
    """
    logging.debug(f"Source version: {source_version}; target version: {target_version}")

    # Unset environment variables from parent image so that pg_upgrade can make its
    # own decisions about which credentials to use
    del os.environ['PGHOST']
    del os.environ['PGPORT']
    del os.environ['PGUSER']
    del os.environ['PGPASSWORD']
    del os.environ['PGDATABASE']

    if not _dir_exists_and_accessible(POSTGRES_DATA_DIR):
        raise PostgresUpgradeError(f"{POSTGRES_DATA_DIR} does not exist or is inaccessible.")

    if getpass.getuser() != POSTGRES_USER:
        raise PostgresUpgradeError(f"This script is to be run as '{POSTGRES_USER}' user.")

    if target_version <= source_version:
        raise PostgresUpgradeError(
            f"Target version {target_version} is not newer than source version {source_version}."
        )

    shm_size = int(shutil.disk_usage("/dev/shm")[0] / 1024 / 1024)
    min_shm_size = int(_ram_size_mb() / 3) - 1024
    if shm_size < min_shm_size:
        raise PostgresUpgradeError(
            f"Container's /dev/shm should be at least {min_shm_size} MB; try passing --shm-size property."
        )

    logging.info("Updating memory configuration...")
    subprocess.check_call(['/opt/mediacloud/bin/update_memory_config.sh'])

    # Remove cruft that might have been left over from last attempt to do the upgrade
    patterns = [
        'pg_*.log',
        'pg_*.custom',
        'pg_upgrade_dump_globals.sql',
    ]
    for pattern in patterns:
        for file in glob.glob(os.path.join(POSTGRES_DATA_DIR, pattern)):
            logging.debug(f"Deleting {file}...")
            os.unlink(pattern)

    new_maintenance_work_mem = int(_ram_size_mb() / 10)
    logging.info(f"New maintenance work memory limit: {new_maintenance_work_mem} MB")
    maintenance_work_mem_statement = f'maintenance_work_mem = {new_maintenance_work_mem}MB'

    # Work out upgrade pairs
    # (initialize the pairs first so that _PostgresVersion() gets a chance to test environment first)
    upgrade_pairs = []
    current_port = 50432
    for version in range(source_version, target_version):
        upgrade_pairs.append(
            _PostgresVersionPair(
                old_version=_PostgresVersion(
                    version=version,
                    target_version=False,
                    starting_version=(version == source_version),
                    port=current_port,
                    extra_postgres_config='',
                ),
                new_version=_PostgresVersion(
                    version=version + 1,
                    target_version=True,
                    starting_version=False,
                    port=current_port + 1,
                    extra_postgres_config=maintenance_work_mem_statement,
                )
            ))
        current_port = current_port + 2

    initial_version = upgrade_pairs[0].old_version
    logging.info("Starting PostgreSQL before upgrade in case the last shutdown was unclean...")
    proc = _PostgreSQLServer(
        port=initial_version.port,
        bin_dir=initial_version.bin_dir,
        data_dir=initial_version.main_dir,
        conf_dir=initial_version.tmp_conf_dir,
    )
    proc.start()
    proc.stop()

    for pair in upgrade_pairs:

        logging.info(f"Upgrading from {pair.old_version.version} to {pair.new_version.version}...")

        logging.info("Running initdb...")
        pathlib.Path(pair.new_version.main_dir).mkdir(parents=True, exist_ok=True)
        subprocess.check_call([
            pair.new_version.initdb,
            '--pgdata', pair.new_version.main_dir,

            # At the time of writing we don't use checksums so we can't enable them here; once (if) they get enabled,
            # this needs to be uncommented
            # '--data-checksums',

            '--encoding', 'UTF-8',
            '--lc-collate', 'en_US.UTF-8',
            '--lc-ctype', 'en_US.UTF-8',
        ])

        upgrade_command = [
            pair.new_version.pg_upgrade,
            '--jobs', str(multiprocessing.cpu_count()),
            '--old-bindir', pair.old_version.bin_dir,
            '--new-bindir', pair.new_version.bin_dir,
            '--old-datadir', pair.old_version.main_dir,
            '--new-datadir', pair.new_version.main_dir,
            '--old-port', str(pair.old_version.port),
            '--new-port', str(pair.new_version.port),
            '--old-options', f" -c config_file={pair.old_version.tmp_conf_dir}/postgresql.conf",
            '--new-options', f" -c config_file={pair.new_version.tmp_conf_dir}/postgresql.conf",
            '--link',
            '--verbose',
        ]

        logging.info("Testing if clusters are compatible...")
        subprocess.check_call(upgrade_command + ['--check'], cwd=POSTGRES_DATA_DIR)

        logging.info("Upgrading...")
        subprocess.check_call(upgrade_command, cwd=POSTGRES_DATA_DIR)

        logging.info("Cleaning up old data directory...")
        shutil.rmtree(pair.old_version.data_dir)

        logging.info("Cleaning up scripts...")
        for script in [
            'analyze_new_cluster.sh',
            'delete_old_cluster.sh',
            'pg_upgrade_internal.log',
            'pg_upgrade_server.log',
            'pg_upgrade_utility.log',
        ]:
            script_path = os.path.join(POSTGRES_DATA_DIR, script)
            if os.path.isfile(script_path):
                os.unlink(script_path)

        logging.info(f"Done upgrading from {pair.old_version.version} to {pair.new_version.version}")

    current_version = upgrade_pairs[-1].new_version

    proc = _PostgreSQLServer(
        port=current_version.port,
        bin_dir=current_version.bin_dir,
        data_dir=current_version.main_dir,
        conf_dir=current_version.tmp_conf_dir,
    )
    proc.start()

    logging.info("Running VACUUM ANALYZE...")
    logging.info("(monitor locks while running that because PostgreSQL might decide to do autovacuum!)")
    subprocess.check_call([
        current_version.vacuumdb,
        '--port', str(current_version.port),
        '--all',
        '--verbose',
        # Do --analyze-only instead of --analyze-in-stages because we're ready to wait for the full statistics
        '--analyze-only',
        '--jobs', str(multiprocessing.cpu_count()),
    ])

    proc.stop()

    logging.info("Done!")


def main():
    parser = argparse.ArgumentParser(description="Upgrade PostgreSQL dataset.")
    parser.add_argument("-s", "--source_version", type=int, required=True,
                        help="Version to upgrade from")
    parser.add_argument("-t", "--target_version", type=int, required=True,
                        help="Version to upgrade to")
    args = parser.parse_args()

    postgres_upgrade(source_version=args.source_version, target_version=args.target_version)


if __name__ == '__main__':
    main()
