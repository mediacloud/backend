<!-- MEDIACLOUD-TOC-START -->

Table of Contents
=================

   * [Workflows](#workflows)
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
