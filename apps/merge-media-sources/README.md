# Merging media sources

## TODO

* Create sample database with fake data
* Test running the same activity multiple times
* If an activity throws an exception, its message should get printed out to the console as well (in addition to
  Temporal's log)
* Track failed workflows / activities in Munin
* Instead (in addition to) of setting `workflow_run_timeout` in `test_workflow.py`, limit retries of the individual
  activities too so that when they fail, we'd get a nice error message printed to the test log
