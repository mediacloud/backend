# Requirements

## Host machine requirements

* **Ubuntu 16.04+, macOS**, or Windows (the latter is untested and might not work at all).

  Media Cloud is tested on works on Ubuntu 16.04 and 18.04. Older Ubuntu versions, e.g. 14.04, might also work but you will most likely encounter various caching discrepancies due to an older Linux kernel version used by 14.04.

  Other Linux distributions, e.g. CentOS, should work fine but running Media Cloud on them is not supported. Windows hosts should technically work as well, but you're absolutely at your own here.

* **Docker 18.09.2**.

  For the sake of your own sanity, make sure that you're running the same version of Docker as in production and testing environments. At the time of writing, said environments run Docker `18.09.2`.

  * To install a specific version of Docker on Ubuntu, refer to the [installation instructions](https://docs.docker.com/install/linux/docker-ce/ubuntu/#install-docker-ce-1) or just use our Ansible playbook which makes sure to install and hold `docker-ce` package at version 18.09.2:

    ```bash
    cd provision/
    ansible-playbook --inventory='localhost,' --connection=local --tags docker setup.yml
    ```

  * To install a specific version of Docker on macOS, download and install [Docker Desktop for Mac build 31259](https://download.docker.com/mac/stable/31259/Docker.dmg) which ships with Docker 18.09.2.

  * To install a specific version of Docker on Windows, download and install [Docker Desktop for Windows build 31259](https://download.docker.com/win/stable/31259/Docker%20for%20Windows%20Installer.exe) which ships with Docker 18.09.2.

* **Docker Compose**.

  On macOS and Windows, Docker Compose will come preinstalled together with Docker Desktop. On Ubuntu, you might want to install it separately using [one of the supported methods](https://docs.docker.com/compose/install/#install-compose). Probably the easiest method is to just install it with Pip:

  ```bash
  $ pip3 install docker-compose
  ```

* **Python 3.5+**.

  Docker Compose and developer scripts are written in Python and require version 3.5 and up.

## Development machine requirements

If you're going to develop and test Media Cloud on your machine, you'll need to install a few more requirements:

* **PyYAML Python module**.

  Developer script `run.py` validates YAML present in `docker-compose.tests.yml` used for testing, so you will need to install PyYAML on your host machine. You can do that with Pip:

  ```bash
  $ pip3 install PyYAML
  ```

* **`parallel` utility**.

  Developer scripts don't bother with parallelization of builds and testing themselves, instead relying on [GNU parallel](https://www.gnu.org/software/parallel/) to run commands in parallel for them. Install the utility on Ubuntu:

  ```bash
  $ apt-get -y install parallel
  ```

  or macOS:

  ```bash
  $ brew install parallel
  ```
