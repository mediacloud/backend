# How to install and develop on Media Cloud

These are very brief, likely incomplete, installation instructions. If you want to install the system, follow these instructions as they are and send any questions to <info@mediacloud.org>.

These instructions assume comfort with Perl, Python, PostgreSQL, and Docker. You may have a difficult time installing the system if you do not have at least some experience with all four of them.


## Steps

1. Install and configure Docker as detailed in our [Requirements](doc/requirements.markdown) page.
2. If you're unfamiliar with Docker, we recommend that you try it out a few tutorials before proceeding further:
    * [Get Started with Docker](https://docs.docker.com/get-started/)
    * [Manage data in Docker](https://docs.docker.com/storage/)
3. Get acquainted with basic Docker and Media Cloud concepts in [Docker concepts](doc/docker_concepts.markdown)
4. Learn how to do common operations with Docker from our [Docker cheat sheet](doc/docker_cheat_sheet.markdown).
5. To be able to change the apps' code and test your changes, you'll find it useful to use the [Development / testing environment](doc/dev_test_environment.markdown)
6. A bunch of developer scripts are here to make it easier to do every day operations; read about them in [Developer scripts](doc/dev_scripts.markdown)
7. Every app has its own PyCharm project; learn how to [configure PyCharm](doc/pycharm.markdown) to run Media Cloud apps
8. Before creating new apps or modifying the current ones, you might want to read through the [Creating apps](doc/creating_apps.markdown)
9. Find out how to pass configuration to app containers in a [Configuration](doc/configuration.markdown) tutorial.
10. Should you need to update the PostgreSQL schema, you should follow the steps detailed in [Updating PostgreSQL schema](doc/schema_migrations.markdown)
11. [Sending email](doc/email.markdown) from apps is easy
12. Most software projects come with a bunch of helper scripts; we keep them in [Tools](doc/tools.markdown)
13. Deploying apps in production is slightly different than running them in a development environment as detailed in [Deploying](doc/deploying.markdown)
14. If you encounter any issues while building and running apps, take a look at [Docker issues](doc/docker_issues.markdown)
15. In certain cases, you might want to [run Docker remotely](doc/docker_remote.markdown)

Perform brilliant analysis, fix our broken code, document how the system works, and otherwise contribute to the project.


## Sample dataset

If you would like to test out Media Cloud with a sample dataset, you can use our [Global Voices](https://globalvoices.org/) database dump available at:

    <https://mediacloud-sample-dumps.s3.amazonaws.com/sample-dumps/mediacloud-globalvoices-unextracted-4616.sql.xz>

Import the dump into a PostgreSQL instance running in a `postgresql-server` app.

Afterwards, you will be able to log in to the web interface using the sample user credentials from `install.sh`, i.e. with username `jdoe@mediacloud.org` and password `mediacloud`.
