# Media Cloud + Gearman interoperability

Media Cloud uses [Gearman](http://gearman.org/) and
[Gearman::JobScheduler](https://github.com/pypt/p5-Gearman-JobScheduler) for
scheduling, enqueueing and running various background processes.


## Installing Gearman

On Ubuntu, install Gearman with:

    apt-get install gearman
    apt-get install libgearman-dev  # for Gearman::XS

On OS X, install Gearman with:

    brew install gearman


## Installing `Gearman-JobScheduler`

`Gearman-JobScheduler` is a normal Carton dependency, so install it by running:

    ./script/run_carton.sh install --deployment


## Configuring Gearman to use PostgreSQL for storing the job queue

You need to set Gearman up to store its job queue in a permanent storage (as
opposed to storing the queue in memory). If you do not do that, Media Cloud
might be unable to correctly keep track of the currently enqueued / running /
finished / failed jobs (see the `gearman_job_queue` table definition in
`script/mediawords.sql` for the explanation).

You might want Gearman to
[store its job queue in PostgreSQL](http://gearman.org/manual:job_server#postgresql).
To do that, create a PostgreSQL database `gearman` for storing the queue, and
allow user `gearman` to access it:

    # sudo -u postgres createuser -D -A -P gearman
    Enter password for new role: 
    Enter it again: 
    Shall the new role be allowed to create more new roles? (y/n) n
    # sudo -u postgres createdb -O gearman gearman

Then, edit `/etc/default/gearman-job-server`:

    vim /etc/default/gearman-job-server

and append PostgreSQL connection properties to `PARAMS` so that it reads
something like this:

    # Parameters to pass to gearmand.
    PARAMS="--listen=127.0.0.1"

    # Use PostgreSQL for storing a job queue
    export PGHOST=127.0.0.1
    export PGPORT=5432
    export PGUSER=gearman
    export PGPASSWORD="correct horse battery staple"
    export PGDATABASE=gearman
    PARAMS="$PARAMS --queue-type Postgres"
    PARAMS="$PARAMS --libpq-table=queue"
    PARAMS="$PARAMS --verbose DEBUG"

Lastly, restart `gearmand`:

    # service gearman-job-server restart
     * Stopping Gearman Server gearmand    [ OK ] 
     * Starting Gearman Server gearmand    [ OK ] 


## Testing Gearman

To try things out, start a test Gearman worker which will count the lines of
the input:

    $ gearman -w -f wc -- wc -l

Then run the job in the worker:

    $ gearman -f wc < /etc/group
    61

Ensure that the job queue is being stored in PostgreSQL:

    # sudo -u postgres psql gearman
    gearman=# \dt
            List of relations
     Schema | Name  | Type  |  Owner  
    --------+-------+-------+---------
     public | queue | table | gearman
    (1 row)

Submit a test background job to Gearman:

    $ gearman -b -f wc < /etc/passwd

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

    $ gearadmin --status
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
