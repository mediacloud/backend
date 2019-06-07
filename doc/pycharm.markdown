# Configuring PyCharm with Docker

This tutorial details on how to set up [PyCharm Professional](https://www.jetbrains.com/pycharm/) to build, test and run Media Cloud apps using Docker and Docker Compose.

Given that Media Cloud consists of multiple applications that make up the whole system, most of apps under `apps/` have their very own PyCharm project. This tutorial can be used both to create PyCharm projects for new apps and update projects for existing apps to make them work.

Unless specified otherwise, most of the configuration options detailed in this tutorial can be found under PyCharm's project preferences (*PyCharm* -> *Preferences…* on macOS). The tutorial is applicable for both macOS and Linux builds of PyCharm, and might even work on Windows.

## Install and configure Docker plugin

PyCharm Docker integration requires *Docker integration* and *Python Docker* plugins to be installed. You have to install the required plugins only once and not for every app project.

To install and configure PyCharm Docker plugins:

1. Open *Plugins*, search for the `Docker` plugin in the *Marketplace* tab, install the plugin, and then restart the IDE:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/docker-plugins-01.png)

2. Open *Build, Execution, Deployment* -> *Docker*, add the local instance of Docker, and name it `mediacloud`:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/docker-plugins-02.png)

3. PyCharm Docker configuration should work now.

## Add PyCharm plugins as project's dependencies

You might want for the IDE to complain if the PyCharm plugins required by the project are not installed.

To add PyCharm plugins as project's dependencies:

1. Open *Build, Execution, Deployment* -> *Required Plugins* and add both *Docker integration* and *Python Docker* as project's dependencies:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/required-plugins-01-plugins.png)

2. From now on, IDE will complain if the required plugins are not installed when project gets opened.

## Configure Python interpreter

Upon creating a PyCharm project for a new Media Cloud app, you might want to configure it to use the Python interpreter from the main container created by the project's `docker-compose.tests.yml` Docker Compose test configuration. This will make your project run the right version of Python, use the dependencies installed in the container, access PostgreSQL database, Solr, RabbitMQ and other services started up by the test configuration, and isolate app's dependencies and environment from other applications that you might be running on your host computer or other containers.

To make the project use Python interpreter from the Docker Compose test configuration:

1. Open *Project: &lt;app-name&gt;* -> *Project Interpreter*:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/interpreter-01-initial-screen.png)

2. Click the wrench icon at the top right, and pick *Add…*:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/interpreter-02-add.png)

3. Choose the *Docker Compose* interpreter type, and configure the new interpreter as follows:

   	1. Set *Server:* to `mediacloud` to run the interpreter's containers on a local Docker instance (configured in *Install and configure Docker plugin*)
    	2. Under `Configuration file(s):`, add the path to the app's `docker-compose.tests.yml` to use services defined in it for your interpreter
    	3. Set *Service:* to the name of the main application's container as defined in `docker-compose.tests.yml`
    	4. If app's `docker-compose.tests.yml` reads any configuration variables from the host machine (in the file it's typically defined as `MC_SOME_CONFIG_VAR: "${MC_SOME_CONFIG_VAR}"`), you can set them under *Environment variables:*
    	5. Set *Python interpreter path:* to `python3` to explicitly run Python 3; the default value `python` will fail because `python` binary / symlink is not available in any of the app container images at the time of writing
    	6. Click *OK* to create the new interpreter

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/interpreter-03-compose.png)

4. The new Docker Compose Python interpreter should get added, and you should be seeing a list of modules installed in the main container of the Compose interpreter; click *OK* to set the project's interpreter to the newly created Docker Compose interpreter:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/interpreter-04-added.png)

5. It will take a while for the IDE to index and cache the available modules in the container:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/interpreter-05-updating.png)

6. After the indexing is finished, you might want to optionally confirm that an IDE was able to determine the correct Python module search paths of the main container. To do that, go back to the *Project Interpreter* configuration, click the wrench icon again, select *Show All…* to list all of the available interpreters, choose the project's interpreter, and at the bottom of the interpreter list window pick the *Show paths for the selected interpreter*.

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/interpreter-06-show-paths.png)

   The list of Python module search paths should include app's custom module search paths (set by `PYTHONPATH` in every `Dockerfile`) for both the app container image itself and all of its parent images, e.g. if `cliff-fetch-annotation` container image gets built on top of `cliff-base`, and `cliff-base` in turn uses `common` as its base image, the Python module search paths list should include paths for all three source directories under `/opt/mediacloud/`:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/interpreter-07-paths.png)

7. Project should be using Docker Compose test configuration for its Python interpreter.

## Configure `Dockerfile` build

PyCharm supports building and tagging Docker images. You might not have to do this often because a typical `docker-compose.tests.yml` mounts volumes with the app's source code to the main container, so one doesn't have to rebuilt the container image to get the new code in in debugging environments, but if you modify `Dockerfile` in any way (e.g. install new dependencies in the container image), you might want to rebuild the container image straight from the IDE.

To add a `Dockerfile` build configuration:

1. Open *Run* -> *Edit Configurations…* menu item:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/dockerfile-01-edit.png)

2. At the top left of the window, click the plus sign and add a new *Docker* -> *Dockerfile* configuration:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/dockerfile-02-add.png)

3. Update the newly added `Dockerfile` build configuration as follows:

   1. Set *Server:* to `mediacloud` in order to build container images on a local Docker instance.
   2. Set *Image tag:* to `dockermediacloud/<app-name>:latest`. You might want the image tag to include the `latest` version because we use `latest` internally to refer to the most recently pulled / built version of a particular image, and so `docker-compose.tests.yml` of every app is configured to run against the `latest` version of an image.
   3. Set *Build options:* to `--cache-from dockermediacloud/<app-name>:latest`. Argument `--cache-from` will allow Docker to reuse the cached layers from a previously built image, making the build considerably faster.
   4. Uncheck the *Run built image* checkbox unless you want to run whatever's defined as `CMD` in the image. In an IDE environment, you probably don't want that because it won't start the dependencies defined in `docker-compose.tests.yml`, and you can run any script from the IDE manually anyway (together with its dependent services) without having to rebuild the container image every time.
   5. At the top right of the window, check the *Share* checkbox to make this build configuration public so that you could later add it to the Git repository.
   6. Click *OK*.

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/dockerfile-03-added.png)

4. `Dockerfile` builds should now be configured. To build `Dockerfile` from an IDE, right-click on a `Dockerfile` and select *Run 'Dockerfile'*:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/dockerfile-04-run.png)

## Configure *pytest*

PyCharm is capable of running *pytest* tests in Docker Compose Python interpreter, complete with debugger support and other features, making debugging easy and convenient.

To configure *pytest* to use Docker Compose Python interpreter:

1. Given that you will probably want to run multiple tests using the very same *pytest* run configuration, you might want to modify the *pytest* run configuration template to later reuse it for every test. To open the template configuration, Open *Run* -> *Edit Configurations…* menu item, and at the tree menu at the left select *Templates* -> *Python tests* -> *pytest*:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/test-01-template.png)

2. Update the *pytest* run template as follows:

   1. Under *Environment variables:*, add the `PERL5LIB` and `PYTHONPATH` environment variables of the app's container image. Without them, PyCharm will override Perl and Python module search paths and so your tests won't be able to find the source code installed by parent container images.

      1. Find out app container image's `PERL5LIB` and `PYTHONPATH` environment variable values by running `docker run --entrypoint env dockermediacloud/<app-name>:latest | grep -E 'PERL5LIB|PYTHONPATH'`, e.g.:

         ```bash
         $ docker run --entrypoint env dockermediacloud/cliff-fetch-annotation:latest | grep -E 'PERL5LIB|PYTHONPATH'
         PERL5LIB=/opt/mediacloud/src/cliff-fetch-annotation/perl:/opt/mediacloud/src/cliff-base/perl:/opt/mediacloud/src/common/perl
         PYTHONPATH=/opt/mediacloud/src/cliff-fetch-annotation/python:/opt/mediacloud/src/cliff-base/python:/opt/mediacloud/src/common/python
         ```

      2. Copy the environment variables and paste them in the *Environment variables* editor window:

         ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/test-02-template-env-vars.png)

   2. In *Before launch:* section, add an *External tool* that will remove all (running and stopped) containers before every run.

      By default, PyCharm won't stop the dependency containers after the test has been finished, and won't recreate dependency containers on subsequent test runs (reusing the "dirty" containers from the previous test run instead), so tests won't work because they expect to run in a "clean slate" environment, i.e. freshly created and started containers without any test datasets that could be potentially stored in them from previous test runs.

      To forcibly remove all (running and stopped) containers before running a test:

      1. In *Before launch:* section at the bottom of the window, click the plus sign to open the *External Tools* picker window. In said window, click the plus sign again to add a new external tool. In the *Edit Tool* window, update the newly added tool as follows:

         1. Set *Name:* to *Remove all containers*
         2. Optionally set *Description:* to *Remove all Docker containers before running a command*
         3. Set *Program:* to `$ProjectFileDir$/../../dev/remove_all_containers.sh` for it to point to `remove_all_containers.sh` shell script
         4. Click *OK*

         ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/test-03-remove-all-containers-tool.png)

      2. Back in the *External Tools* window, check the *Remove all containers* tool and uncheck the other tools (if any), then click *OK*

         ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/test-04-ext-tools.png)

   3. After configuring the environment variables and the external tools in the *pytest* run template, save the template by clicking *OK*

      ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/test-05-template-updated.png)

   4. *pytest* run template should now be configured to use Docker Compose to run the tests, set the right environment variables in the main container, and remove all running and stopped containers before every run. To run a test using the *pytest* run template, right click on any test file and select *Run 'pytest in &lt;test_filename&gt;…'*:

      ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/test-06-run.png)

## Configure script run template

In addition to tests, you might want to run any other Python script in the Docker Compose test environment too. Configuring it is very similar to how *pytest* run configuration template gets configured, it's just that instead of *pytest* you'll be running vanilla Python binary.

To configure script run template to use Docker Compose Python interpreter:

1. Open *Run* -> *Edit Configurations…* menu item, and at the tree menu at the left select *Templates* -> *Python tests*.

2. Update the script run template by adding custom environment variables and an external build tool just like how it's done in the *pytest* run configuration (see *Configure pytest* section above):

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/run-01-template.png)

3. Script run template should now be configured to use Docker Compose to run the scripts, set the right environment variables in the main container, and remove all running and stopped containers before every run. To run a script using the template, right click on any script and select *Run '&lt;script_filename&gt;…'*:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/run-02-run.png)

## Configure IDE's Python Console

PyCharm's *Python Console* (one of the tabs at the bottom of the main IDE window) is a handy Python REPL that you can use to run arbitrary Python code in the main container of the app.

To set up *Python Console*:

1. Open *Build, Execution, Deployment* -> *Console* -> *Python Console*

2. Add the custom custom environment variables just like how it's done in the *pytest* run configuration (see *Configure pytest* section above) and click *OK*:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/console-01-env-vars.png)

3. You should be able to use the *Python Console* tool now; upon initialization, the tool will start the main container's dependencies and set up the Perl / Python library search paths so that you could import modules from the app itself and its parent container images:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/console-02-running.png)

## Configure default test runner

PyCharm tries to auto-determine the default test runner for every app but sometimes fails to do so.

To make sure that you'll be always using *pytest* to run tests:

1. Open *Tools* -> *Python Integrated Tools* and make sure that *Default test runner:* is set to *pytest*.

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/default-test-runner-01-runner.png)

2. From this point on, IDE will run every Python test using *pytest*.

## Configure SQL schema

Without the SQL schema dialect and data source configuration, PyCharm will complain about not being able to identify the schema dialect and verify that objects referred to in various SQL queries do exist in the schema:

![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/schema-01-dialect-warning.png)

To configure SQL schema dialect and data source:

1. Go to *Languages & Frameworks* -> *SQL Dialects*, set the *Project SQL Dialect:* to *PostgreSQL* and click *OK*:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/schema-02-dialect-project.png)

2. Open the database tool window by choosing *View* -> *Tool Windows* -> *Database* in the menu:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/schema-03-data-source-menu.png)

3. In the database tool window on the right, add a new DDL data source by clicking on the plus sign and choosing *DDL Data Source*:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/schema-04-data-source-ddl.png)

4. Leave the default value of the *Name:* field intact and under *DDL Files*, add a `media words.sql` file (located in the `postgresql-server` app under `schema/mediawords.sql`) and click *OK*:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/schema-05-data-source-mediawords.png)

5. In the subsequent window, click on the cell under the *SQL Dialect* column in the row with `mediawords.sql` entry, choose the *PostgreSQL* dialect and click *OK*:

   ![](https://github.com/berkmancenter/mediacloud-docs-images/raw/master/docker-pycharm/schema-06-data-source-postgresql.png)

6. SQL dialect and data source is now configured, IDE should be able to use the newly added configuration to warn you of problems with your SQL queries.
