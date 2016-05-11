# Job manager

Media Cloud uses [MediaCloud::JobManager](https://github.com/berkmancenter/p5-MediaCloud-JobManager) for
managing job queues.


## Starting a worker

To start a single instance of a worker, run:

    ./script/run_with_carton.sh local/bin/mjm_worker.pl lib/MediaWords/Job/RescrapeMedia.pm

To start a single instance of *all* workers in a subdirectory, run:

    ./script/run_with_carton.sh local/bin/mjm_worker.pl lib/MediaWords/Job/


## Running a job

To add a job to the worker queue, run:

    MediaWords::Job::RescrapeMedia->add_to_queue();

To pass arguments to the worker, add them as a hashref parameter:

    MediaWords::Job::RescrapeMedia->add_to_queue({ one => 'two', three => 'four' });

`add_to_queue()` returns a job ID if the job was added to queue successfully:

    my $job_id = MediaWords::Job::RescrapeMedia->add_to_queue();

You can use the job ID to *cancel job which isn't running yet*:

    MediaCloud::JobManager::Admin::cancel_job(
        MediaWords::Job::RescrapeMedia->configuration(),
        $job_id
    );


## Job brokers


### RabbitMQ

Media Cloud supports using [RabbitMQ](https://www.rabbitmq.com/) as a job broker. Clients and workers will interact using [Celery](http://www.celeryproject.org/) protocol.

#### Running

Run `./script/rabbitmq_wrapper.sh` which will start a separate RabbitMQ server instance on port 5673 and a web interface on port [15673](http://localhost:15673/).


#### Monitoring

Use RabbitMQ's web interface at <http://localhost:15673/> (default username: `mediacloud`; default password: `mediacloud`).


### Gearman

#### Running

While you can use your system's Gearman deployment directly, it is recommended
that you use another instance configured by Media Cloud and managed by
Supervisor because:

1. `gearmand` will automatically use PostgreSQL as a backend for storing a job
   queue (instead of an unsafe in-memory job queue used by Gearman by default).
2. Logs will be available in `data/supervisor_logs/`.

Gearman is automatically started by Supervisor. See
`README.supervisor.markdown` for instructions on how to manage Supervisor
processes.


#### Testing

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


#### Monitoring

To monitor Gearman, you can use either the `gearadmin` tool or the
"Gearman-Monitor" PHP script.


### `gearadmin`

For example:

    $ gearadmin -h 127.0.0.1 -p 4731 --status
    wc  2   0   0

(Function "wc", 2 jobs in the queue, 0 currently running, 0 workers registered)

Run `gearadmin --help` for more options.


##### "Gearman-Monitor"

[Gearman-Monitor](https://github.com/yugene/Gearman-Monitor) is a tool to watch
Gearman servers. 

Screenshots: http://imgur.com/a/RjJWc
 

## Running jobs on Gearman with `MediaCloud::JobManager`

A full example of a Gearman job is located in:

* `script/mediawords_add_default_feeds.pl` (client)
* `lib/MediaWords/Job/RescrapeMedia.pm` (worker)
