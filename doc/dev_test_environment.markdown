# Development / testing environment

Every app with tests also has to have a Docker Compose test configuration `docker-compose.tests.yml` which defines how the app itself and its dependencies will be run for every test file in the app's test suite.

Using the test configuration, the test runner creates a "clean slate" environment for every test file of the app, runs the test in this environment, cleans up the environment after the test finishes, and lastly reports back the test result.

Every test file (as opposed to the test) gets its own fresh test environment to run in. Independently from which specific dependency apps (PostgreSQL, Solr, RabbitMQ, …) does the test actually use (e.g. connect to, read from or write to), all of the dependencies get started for each and every test file.

Given that the app's tests don't get built into an app's container image, the whole `<app-name>/tests/` directory gets mounted as a volume to the `/opt/mediacloud/tests/` path in the main container instead. Additionally, source directories of both the main app and its parent images (if any) get mounted in their respective locations under `/opt/mediacloud/src/` on top of the existing files that got copied there as part of the build; this allows one to start a development environment using `docker-compose.tests.yml` via the `run.py` developer script and edit the source code on a host machine while running it in the Compose environment without having to rebuild the app's container image after source code change in the app itself or its parents.

The very same Compose testing environment can be used for developing the app - `run.py` developer script will create a new testing environment using the very same `docker-compose.tests.yml` which you can use to try out updates to your branch.

## Importing data into Solr

To import stories into Solr from within the test file:

1. Add `import-solr-data-for-testing` worker to the tested app's `docker-compose.tests.yml`;

2. In the test, add a job to the `MediaWords::Job::ImportSolrDataForTesting` queue and wait for it to complete using `run_remotely()` helper, e.g.:

   ```perl
   MediaWords::JobManager::Job::run_remotely(
       'MediaWords::Job::ImportSolrDataForTesting',
       { throttle => 0 },
   );
   ```

If you use `MediaWords::Test::Solr::setup_test_index()` helper to import test stories to Solr, it will do the importing for you.
