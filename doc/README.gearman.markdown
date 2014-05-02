# Media Cloud + Gearman interoperability

Media Cloud uses [Gearman](http://gearman.org/) and
[Gearman::JobScheduler](https://github.com/pypt/p5-Gearman-JobScheduler) for
scheduling, enqueueing and running various background processes.


## Starting Gearman

While you can use your system's Gearman deployment directly, it is recommended
that you use another instance configured by Media Cloud and managed by
Supervisor because:

1. `gearmand` will automatically use PostgreSQL as a backend for storing a job
   queue (instead of an unsafe in-memory job queue used by Gearman by default).
2. Logs will be available in `data/supervisor_logs/`.

Gearman is automatically started by Supervisor. See
`README.supervisor.markdown` for instructions on how to manage Supervisor
processes.


## Testing Gearman

To try things out, start a test Gearman worker which will count the lines of
the input:

    $ gearman -h 127.0.0.1 -p 4731 -w -f wc -- wc -l

Then run the job in the worker:

    $ gearman -h 127.0.0.1 -p 4731 -f wc < /etc/group
    61

Ensure that the job queue is being stored in PostgreSQL:

    # sudo -u postgres psql mediacloud_gearman
    gearman=# \dt
            List of relations
     Schema | Name  | Type  |  Owner  
    --------+-------+-------+---------
     public | queue | table | gearman
    (1 row)

Kill the worker process and submit a test background job to Gearman:

    $ gearman -h 127.0.0.1 -p 4731 -b -f wc < /etc/passwd

and make sure it is being stored in the queue:

    gearman=# SELECT COUNT(*) FROM queue;
     count 
    -------
         1
    (1 row)


## Monitoring Gearman

To monitor Gearman, you can use either the `gearadmin` tool or the
"Gearman-Monitor" PHP script.


### `gearadmin`

For example:

    $ gearadmin -h 127.0.0.1 -p 4731 --status
    wc  2   0   0

(Function "wc", 2 jobs enqueued, 0 currently running, 0 workers registered)

Run `gearadmin --help` for more options.


### "Gearman-Monitor"

[Gearman-Monitor](https://github.com/yugene/Gearman-Monitor) is a tool to watch
Gearman servers. 

Screenshots: http://imgur.com/a/RjJWc


## Running jobs on Gearman with `Gearman::JobScheduler`

A full example of a Gearman job is located in:

* `script/mediawords_add_default_feeds.pl` (client)
* `lib/MediaWords/GearmanFunction/AddDefaultFeeds.pm` (worker)


### Starting a Gearman worker

To start a single instance of the Gearman worker, run:

    ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/AddDefaultFeeds.pm

To start a single instance of *all* Gearman workers in a subdirectory, run:

    ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/

To start 4 instances of the Gearman worker, run:

    ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/AddDefaultFeeds.pm 4

To start 4 instances of *all* Gearman workers in a subdirectory, run:

    ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/ 4


### Running a job

To enqueue a job for the worker, run:

    MediaWords::GearmanFunction::AddDefaultFeeds->enqueue_on_gearman();

To pass arguments to the worker, add them as a hashref parameter:

    MediaWords::GearmanFunction::AddDefaultFeeds->enqueue_on_gearman({ one => 'two', three => 'four' });

`enqueue_on_gearman()` returns a Gearman job ID if the job was enqueued successfully:

    my $gearman_job_id = MediaWords::GearmanFunction::AddDefaultFeeds->enqueue_on_gearman();

You can use the job ID to *get the path to the log of the running job*:

    my $log_path = Gearman::JobScheduler::log_path_for_gearman_job(
        MediaWords::GearmanFunction::AddDefaultFeeds->name(),
        $gearman_job_id
    );

Or to *cancel an enqueued job which isn't running yet*:

    Gearman::JobScheduler::cancel_gearman_job(
        MediaWords::GearmanFunction::AddDefaultFeeds->name(),
        $gearman_job_id
    );

Or to *get the job status of enqueued / running Gearman job*:

    print Dumper( Gearman::JobScheduler::job_status(
        MediaWords::GearmanFunction::AddDefaultFeeds->name(),
        $gearman_job_id
    ));
