
create view pending_job_states as select * from job_states where state in ( 'running', 'queued' );



