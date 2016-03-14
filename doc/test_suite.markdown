# Test suite setup

If you have not already done so, create a test database and add it to `mediawords.yml` with the label `test` as
described in the `INSTALL` file.

Note that this database is wiped and rewritten every time the test suite is run.

## Running the Full Test Suite

Normally the best way to run the full test suite is to run `./script/run_test_suite.sh`. This will run all of the tests
and then report a summary of any failures.

In addition, if you have touched anything that might impact the api, you should separately run
`./api_test/run_api_test.sh`.  This command will run a small perl test suite against the api.

To run more extensive api tests, set 'MEDIACLOUD_ENABLE_PYTHON_API_TESTS' before running run_api_test.sh.  This will
make the test suite use the test suite developed for the Media Cloud python client.  Both the python client and the
python client test suite are hosted in a separate github repo and so require some additional setup to run. See
api_test/notes.txt for notes on that extra setup.

The following scripts may also be useful.

* `./script/run_test_suite_with_code_update.sh` -- this script preforms a full git pull on the source tree
before running the test suite

* `./script/run_test_suite_for_cron.sh* -- runs the `run_test_suite_with_code_update.sh` script but only produces output
if one of the tests fails.

*Note:* It's normal for the full test suite to fail when you run it on a new test database for the first time. Simply
run it a second time in this case.

## Running a Single Test

The above commands only report a summary of the errors.  If there are errors, it is usually useful to only run a single
test to show the detailed errors. To run a single test, use:

    ./script/run_carton.sh exec prove -Ilib/ -r <TEST_FILE_NAME>

e.g.:

    ./script/run_carton.sh exec prove -Ilib/ -r t/compile.t

## Automated Testing

### Vagrant

To setup a virtual host from scratch using vagrant and run the tests on the fresh virtual host, run
`run_install_test_suite_on_vagrant.sh`.  See [vagrant.markdown](vagrant.markdown) for detailed instructions about
how to setup and run vagrant with Media Cloud.  We run this script nightly on our production system to make sure that
the mast branch of Media Cloud is passing its test suite from a fresh install.

### Tavis

In addition to the nightly vagrant tests, we have an account on TavisCI that runs the full test suite, including api
tests, on every commit+push.  Project developers are emailed whenever a TavisCI commit test run fails.
