# Test suite setup

If you have not already done so, create a test database and add it to `mediawords.yml` with the label `test` as described in the `INSTALL` file.

Note that this database is wiped and rewritten everytime the `test_suite` is run.

## Running the Full Test Suite

Normally the best way to run the full test suite is to run `./script/run_test_suite.sh`

This will run all of the tests and then report a summary of any failures.

The following scripts may also be useful.

* `./script/run_test_suite_with_code_update.sh` -- this script preforms a full subversion update on the source tree before running the test suite

* `./script/run_test_suite_for_cron.sh* -- runs the `run_test_suite_with_code_update.sh` script but only produces output if one of the tests fails.

*Note:* It's normal for the full test suite to fail when you run it on a new test database for the first time. Simply run it a second time in this case.

## Running a Single Test

Sometimes it's useful to only run a simple test. To do this use the `./script/run_carton.sh` to invoke the prove program directly as follows:

    ./script/run_carton.sh exec prove -Ilib/ -r <TEST_FILE_NAME>

e.g.:

    ./script/run_carton.sh exec prove -Ilib/ -r t/compile.t
