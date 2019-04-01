# Job manager

## Starting a worker

To start a single instance of a worker, run:

    mjm_worker.pl lib/MediaWords/Job/RescrapeMedia.pm

To start a single instance of *all* workers in a subdirectory, run:

    mjm_worker.pl lib/MediaWords/Job/


## Running a job

To add a job to the worker queue, run:

    MediaWords::JobManager::Job::add_to_queue('MediaWords::Job::RescrapeMedia');

To pass arguments to the worker, add them as a hashref parameter:

    MediaWords::JobManager::Job::add_to_queue('MediaWords::Job::RescrapeMedia', { one => 'two', three => 'four' });

`add_to_queue()` returns a job ID if the job was added to queue successfully:

    my $job_id = MediaWords::JobManager::Job::add_to_queue('MediaWords::Job::RescrapeMedia');


## Job brokers


### RabbitMQ

Media Cloud supports using [RabbitMQ](https://www.rabbitmq.com/) as a job broker. Clients and workers will interact using [Celery](http://www.celeryproject.org/) protocol.

#### Running

Run `./script/rabbitmq_wrapper.sh` which will start a separate RabbitMQ server instance on port 5673 and a web interface on port [15673](http://localhost:15673/).


#### Monitoring

Use RabbitMQ's web interface at <http://localhost:15673/> (default username: `mediacloud`; default password: `mediacloud`).

To connect to RabbitMQ web interface at _mcdb1_, create a SSH tunnel as such:

    ssh mcdb1 -L 15673:localhost:15673 -N
