<!-- MEDIACLOUD-TOC-START -->

Table of Contents
=================

   * [Workflows](#workflows)
      * [Samples](#samples)
         * [Retry parameters](#retry-parameters)
         * [Activity interface](#activity-interface)
         * [Activity interface with custom retries](#activity-interface-with-custom-retries)
         * [Workflow interface](#workflow-interface)
         * [Running a workflow](#running-a-workflow)
            * [Asynchronously](#asynchronously)
            * [Synchronously](#synchronously)
      * [Tips &amp; tricks](#tips--tricks)
         * [Name workflow (activity) interface as XYZWorkflow (<code>XYZActivities</code>), implementation as <code>XYZWorkflowImpl</code> (<code>XYZActivitiesImpl</code>)](#name-workflow-activity-interface-as-xyzworkflow-xyzactivities-implementation-as-xyzworkflowimpl-xyzactivitiesimpl)
         * [Make activities idempotent](#make-activities-idempotent)
         * [Limit activity invocations in a single workflow to 1000](#limit-activity-invocations-in-a-single-workflow-to-1000)
         * [Limit the activity payload to 200 KB](#limit-the-activity-payload-to-200-kb)
         * [Use positional arguments](#use-positional-arguments)
         * [Make arguments serializable by encode_json()](#make-arguments-serializable-by-encode_json)
         * [Use connect_to_db_or_raise() instead of <code>connect_to_db()</code>](#use-connect_to_db_or_raise-instead-of-connect_to_db)
         * [Use stop_worker_faster() to stop local workers used in tests](#use-stop_worker_faster-to-stop-local-workers-used-in-tests)
         * [Reuse WorkflowClient objects when possible](#reuse-workflowclient-objects-when-possible)
      * [Links](#links)

----
<!-- MEDIACLOUD-TOC-END -->

# Workflows


## Samples


### Retry parameters

```python
DEFAULT_RETRY_PARAMETERS = RetryParameters(

    # InitialInterval is a delay before the first retry.
    initial_interval=timedelta(seconds=1),

    # BackoffCoefficient. Retry policies are exponential. The coefficient specifies how fast the retry interval is
    # growing. The coefficient of 1 means that the retry interval is always equal to the InitialInterval.
    backoff_coefficient=2,

    # MaximumInterval specifies the maximum interval between retries. Useful for coefficients more than 1.
    maximum_interval=timedelta(hours=2),

    # MaximumAttempts specifies how many times to attempt to execute an Activity in the presence of failures. If this
    # limit is exceeded, the error is returned back to the Workflow that invoked the Activity.

    # We start off with a huge default retry count for each individual activity (1000 attempts * 2 hour max. interval
    # = about a month worth of retrying) to give us time to detect problems, fix them, deploy fixes and let the workflow
    # system just handle the rest without us having to restart workflows manually.
    #
    # Activities for which retrying too much doesn't make sense (e.g. due to the cost) set their own "maximum_attempts".
    maximum_attempts=1000,

    # NonRetryableErrorReasons allows you to specify errors that shouldn't be retried. For example retrying invalid
    # arguments error doesn't make sense in some scenarios.
    non_retryable_error_types=[

        # Counterintuitively, we *do* want to retry not only on transient errors but also on programming and
        # configuration ones too because on programming / configuration bugs we can just fix up some code or
        # configuration, deploy the fixes and let the workflow system automagically continue on with the workflow
        # without us having to dig out what exactly has failed and restart things.
        #
        # However, on "permanent" errors (the ones when some action decides that it just can't proceed with this
        # particular input, e.g. process a story that does not exist) there's no point in retrying anything.
        # anything anymore.
        McPermanentError.__name__,

    ],
)
```


### Activity interface

```python
class SampleActivities(object):

    @activity_method(
        task_queue=TASK_QUEUE,

        # ScheduleToStart is the maximum time from a Workflow requesting Activity execution to a worker starting its
        # execution. The usual reason for this timeout to fire is all workers being down or not being able to keep up
        # with the request rate. We recommend setting this timeout to the maximum time a Workflow is willing to wait for
        # an Activity execution in the presence of all possible worker outages.
        schedule_to_start_timeout=None,

        # StartToClose is the maximum time an Activity can execute after it was picked by a worker.
        start_to_close_timeout=timedelta(seconds=60),

        # ScheduleToClose is the maximum time from the Workflow requesting an Activity execution to its completion.
        schedule_to_close_timeout=None,

        # Heartbeat is the maximum time between heartbeat requests. See Long Running Activities.
        # (https://docs.temporal.io/docs/concept-activities/#long-running-activities)
        heartbeat_timeout=None,

        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def sample_activity(self, stories_id: int) -> Optional[str]:
        raise NotImplementedError
```


### Activity interface with custom retries

```python
class SampleActivities(object):

    @activity_method(
        task_queue=TASK_QUEUE,
        schedule_to_start_timeout=None,
        start_to_close_timeout=timedelta(seconds=60),
        schedule_to_close_timeout=None,
        heartbeat_timeout=None,
        retry_parameters=dataclasses.replace(
            DEFAULT_RETRY_PARAMETERS,

            # Wait for a minute before trying again
            initial_interval=timedelta(minutes=1),

            # Hope for the server to resurrect in a week
            maximum_interval=timedelta(weeks=1),

            # Don't kill ourselves trying to hit a permanently dead server
            maximum_attempts=50,
        ),
    )
    async def another_sample_activity_with_custom_retries(self, stories_id: int) -> Optional[str]:
        raise NotImplementedError
```


### Workflow interface

```python
class SampleWorkflow(object):

    @workflow_method(task_queue=TASK_QUEUE)
    async def sample_workflow_method(self, stories_id: int) -> None:
        raise NotImplementedError
```


### Running a workflow


#### Asynchronously

"Fire and forget" about the workflow:

```python
from mediawords.workflow.client import workflow_client


client = workflow_client()
workflow: SampleWorkflow = client.new_workflow_stub(
    cls=SampleWorkflow,
    workflow_options=WorkflowOptions(workflow_id=str(stories_id)),
)

await WorkflowClient.start(workflow.sample_workflow_method, stories_id)
```


#### Synchronously

Start a workflow and wait for it to complete:

```python
from mediawords.workflow.client import workflow_client


client = workflow_client()
workflow: SampleWorkflow = client.new_workflow_stub(
    cls=SampleWorkflow,
    workflow_options=WorkflowOptions(workflow_id=str(stories_id)),
)

result = await workflow.transcribe_episode(stories_id)
```


## Tips & tricks


### Name workflow (activity) interface as `XYZWorkflow` (`XYZActivities`), implementation as `XYZWorkflowImpl` (`XYZActivitiesImpl`)

Temporal's webapp uses the interface's class name as the workflow name by default, so that way the workflow names look better and are more easily searchable.

```python
# Good!

class KardashianActivities(object):

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=60),
    )
    async def add_new_kardashian(self) -> None:
        # ...

class KardashianActivitiesImpl(KardashianActivities):

    async def add_new_kardashian(self) -> None:
        # ...


class KardashianWorkflow(object):

    @workflow_method(task_queue=TASK_QUEUE)
    async def keep_up_with_kardashians(self) -> None:
        # ...

class KardashianWorkflowImpl(KardashianWorkflow):

    async def keep_up_with_kardashians(self) -> None:
        # ...
```


### Make activities idempotent

Temporal guarantees at-least-once activity invocations, so some activities might have to be rerun occasionally:

```python
# Bad!

class KardashianActivitiesImpl(KardashianActivities):

    async def add_new_kardashian(self) -> None:
        db = connect_to_db_or_raise()

        # If this activity gets run twice, we'll end up with two Kims in the
        # "kardashians" table which is against our strategic goals
        db.query("""
            INSERT INTO kardashians (name, surname)
            VALUES ('Kim', 'Kardashian')
        """)
```

Therefore, activities need to be "ready" for getting run twice sometimes:

```python
# Good!

class KardashianActivitiesImpl(KardashianActivities):

    async def add_new_kardashian(self) -> None:
        db = connect_to_db_or_raise()

        # Here we're assuming that there's a unique index on (name, surname)
        # and using the ON CONFLICT upsert:
        # https://www.postgresql.org/docs/current/sql-insert.html#SQL-ON-CONFLICT
        db.query("""
            INSERT INTO kardashians (name, surname)
            VALUES ('Kim', 'Kardashian')
            ON CONFLICT (name, surname) DO NOTHING
        """)
```


### Limit activity invocations in a single workflow to 1000

While workflow count itself is largely unlimited, the history size (where action invocations get logged to) is [limited to 10 MB (soft limit) / 50 MB (hard limit)](https://github.com/temporalio/temporal/blob/v1.7.0/service/history/configs/config.go#L380-L381), and history count is limited to [10k (soft limit) / 50k (hard limit) entries](https://github.com/temporalio/temporal/blob/v1.7.0/service/history/configs/config.go#L382-L383).

Given that an activity might get retried a few times, and those retries will end up in the workflow's history too, don't invoke too many activities in a single workflow run.

Instead, go for **hierarchical workflows.** For example, if an activity fetches an URL, and you're planning on fetching 1 million URLs, you can make a parent workflow start 1000 children workflows and wait for their completion.

<!-- FIXME add an example -->
<!-- FIXME ContinueAsNew once that becomes available in the Python SDK -->


### Limit the activity payload to 200 KB

Activity arguments get serialized into JSON, sent over the network and then unserialized, so passing around huge JSON payloads hits the performance. Also, payloads are visible in the web UI so loading a huge JSON file in the Temporal's webapp is not practical.

Instead of passing around huge chunks of data in payloads, store it somewhere in the database.


### Use positional arguments

At the time of writing, the Python SDK is unable to serialize named arguments (`**kwargs`) and pass them to workflow / action methods:

```python
# Bad!
await workflow.transcribe_episode(stories_id=stories_id)
```

so positional arguments (`*args`) have to be used instead:

```python
# Good!
await workflow.transcribe_episode(stories_id)
```


### Make arguments serializable by `encode_json()`

Python SDK serializes arguments to workflow and individual activities with `encode_json()`, and the default `JSONEncoder` is [limited](https://docs.python.org/3/library/json.html#json.JSONEncoder) in what it's able to serialize:

```python
# Bad!

class FancyObject(object):
    def __init__(self, fancy_argument: int):
        self.fancy_argument = fancy_argument

class FancyActivities(object):

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=60),
    )
    async def fancy_activity(self, fancy: FancyObject) -> bool:
        # <...>
```

Instead, opt for simple dicts:

```python
# Good!

from typing import Dict, Any

class FancyObject(object):
    def __init__(self, fancy_argument: int):
        self.fancy_argument = fancy_argument

    def to_dict(self) -> Dict[str, Any]:
        return {
            'fancy_argument': self.fancy_argument,
        }

    @classmethod
    def from_dict(self, input_dict: Dict[str, Any]) -> 'FancyObject':
        return cls(fancy_argument=fancy_argument)

class FancyActivities(object):

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=60),
    )
    async def fancy_activity(self, fancy: Dict[str, Any]) -> bool:
        # Convert back to an object
        fancy = FancyObject.from_dict(fancy)
        # <...>
```

or define a new `typing` type to make it more obvious what the activity method is supposed to find in the argument dictionary:

```python
# Better (somewhat)!

from typing import Dict, Any

FancyObjectDict = Dict[str, Any]

class FancyObject(object):
    def __init__(self, fancy_argument: int):
        self.fancy_argument = fancy_argument

    def to_dict(self) -> FancyObjectDict:
        return {
            'fancy_argument': self.fancy_argument,
        }

    @classmethod
    def from_dict(self, input_dict: FancyObjectDict) -> 'FancyObject':
        return cls(fancy_argument=fancy_argument)

class FancyActivities(object):

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=60),
    )
    async def fancy_activity(self, fancy: FancyObjectDict) -> bool:
        # Convert back to an object
        fancy = FancyObject.from_dict(fancy)
        # <...>
```


### Use `connect_to_db_or_raise()` instead of `connect_to_db()`

By default, `connect_to_db()` will attempt connecting to the database quite a few times, and if it fails to do so, it will call `fatal_error()` thus stopping the whole application that has called the function.

Temporal implements retries itself, plus it's not beneficial to quit the worker on database connection issues (as the worker then should continue on retrying), so instead of `connect_to_db()` go for `connect_to_db_or_raise()` which attempts connecting to PostgreSQL only once, and raises a simple exception on failures instead of stopping the whole application.


### Use `stop_worker_faster()` to stop local workers used in tests

Default implementation of `worker.stop()` waits for the whole 5 seconds between attempts to stop all the worker threads. Our own hack implemented in `stop_worker_faster()` tests whether the workers managed to stop every 0.5 seconds.

This is useful in tests in which we run local workers and want to stop them afterwards.


### Reuse `WorkflowClient` objects when possible

Try avoiding creating a new `WorkflowClient` object often as ["it is a heavyweight object that establishes persistent TCP connections"](https://github.com/uber/cadence/issues/2528#issuecomment-530894674).


## Links

* [Main Temporal website](https://temporal.io/)
* [Temporal Python SDK](https://github.com/firdaus/temporal-python-sdk)
    * [Tests with many usage samples](https://github.com/firdaus/temporal-python-sdk/tree/master/tests)
* ["Workflows in Python using Temporal"](https://onepointzero.app/workflows-in-python-using-temporal/), a blog post by the author of the Python SDK with many examples
* [Workflow samples in Go](https://github.com/temporalio/samples-go), many of which adaptable to Python
    * [Mutex workflow sample](https://github.com/temporalio/samples-go/tree/master/mutex)
