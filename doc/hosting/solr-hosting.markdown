Solr Hosting
============

Generic Information
-------------------

We are currently running on Solr 4.6.  All of the below applies to that specific version of solr.

SolrCloud requires a fair amount of hand holding to get all of the shards (individual cluster server instances) running
together happily.  The basic idea is that you run one shard as the leader of the cluster, telling it the total
number of members of the clsuter.  That instance runs zookeeper, the apache system for managing server distribution
(configuration, synchronization, etc).  Then  you individually start each other member of the cluster and just point
each one at the leader.  There is no single solr command to create or start an entire cluster of shards.

To simplify cluster creation, startup, and configuration reloads, we have some local scripts that manage these tasks.
All of these scripts live in solr/scripts and must be run under carton
(script/run_with_carton.sh solr/scripts/create_solr_shards.pl ...).

### Cluster Creation

`create_solr_shards.pl -  create local solr shard directories`

Every shard is just a solr server instance that lives in its own directory.  This command creates
solr/mediacloud-shard-<N> directories to host the individual shareds (solr/mediacloud-shard-1, ...) by copying
solr/mediacloud into each shared directory.  You must specify the number of local shards to create.  If the total
number of shards is specified, the script sets up one of the clusters as the zookeeper / leader of the cluster
(which requires briefly starting up the java instance).

So to create a new cluster, run the below command first on the server that will host the cluster leader with
the number of local and total shards specified and then on each follower server with only the number of local shards
specified.

`usage: create_solr_shards.pl --local_shards <num local shards> [ --total_shards <num total shards> ]`

### Cluster Startup

`start_solr_shards.pl - start up all of the local shards`

Starting the solr cluster requires running a complex java command line for each shard running on each server in the
server.  This script simplifies cluster startup by starting all of the shards on the given server with the correct
java command line.

The startup script knows how many shards it should run on the current server, so you need only specify the
amount of java heap memory to use for each shard, the host of the local machine running those shards, and the
host name of the cluster leader.

The --zk_host option should specify the name of the zookeeper host,
followed by :9983, for example `mcquery2:9983`.

`usage: start_solr_shards.pl --memory <gigs of memory for java heap> --host <local hostname> --zk_host <zk host in host:port format>`

### Cluster Shutdown

To shut down a cluster, just kill the individual shard processes.  Some shards will occasionally fail to shutdown,
in which case 'kill -9' them after a waiting for a minute.

### Cluster Configuration

`reload_solr_shards.pl - load new configuration onto all cluster members`

Once the solr cluster has been created, the shards read their configuration information from the zookeeper rather
than from their local configuration files.  This script loads configuration information from the local directory of
the zookeeper shard (which is mediacloud-shard-1 on the leader host) into zookeeper and then tells each shard
individually to reload its configuration data from the leader.  This should be run on the zookeeper host.

Note that the leader does not know the identity of the other hosts, so you have to specify the name of each server
hosting shards other than the zookeeper host using the --host options.

After running reload, you can connect to the individual shards (for instance http://localhost:8983/solr/) and load
the configuration page to verify that a given configuration change has made it into the running shard.

`usage: $0 --num_shards < total number of shards > --zk_host < zoo keeper host > [ --host < host > ... ]`

MIT Specific Instructions
-------------------------

The solr installation consists of four machines -- mcquery[1234].  We run the solr cluster on three of those machines
and keep the fourth machine as a cold spare.  Each of the machines is a nearly identical dell rack server with 16 cores
and 192G RAM.  [234] have a 360G RAID1'd system disk.  [1] has a slower 600G RAID1'd system disk.  All four members
of the array run solr on an SSD array mounted on /data.  The SSD array runs on 4 RAID10'd 500G SSDs.

We run a cluster of 24 shards, with each active server running 8 shards.  Most of solr's parallel capacity comes from
the individual shards rather than from threading on an individual shard, so we need lots of shards to take advantage
of all of our cores.

We are currently running our cluster in mcquery[124].  mcquery3 corrupted some data during the last full import, and we need to do a diagnosis to figure out if there's something goofy before using
the machine again.

mcquery2 runs the leader shard.  mcquery2 is also the machine that runs the hourly import script, even though we
could run the import on any of the shards.

The mediacloud installation on each of these machines is under /data/mediacloud.  Solr is in /data/mediacloud/solr.
Each server has a full mediacloud install, with the configuration pointing to localhost:6001 as the postgres
port.  There should be an ssh process tunneling 6001 to postgres on the production db (currently mcdb1).

The only thing the mediacloud install is used for on these machines (other than the solr installation) is the import
process.  mcquery2 runs the hourly import script.  The other cluster machines only need to run an import when doing
a full import (just to speed up the process).

We currently use the following command to start the shards under the mediacloud account on each of the machines,
replacing the --host option with the name of the local host.  From /data/mediacloud:

`script/run_with_carton.sh solr/scripts/start_solr_shards.pl --memory 20 --host mcquery2 --zk_host mcquery2:9983`

We keep our zookeeper configuration master in mcquery2:/data/mediacloud/solr/mediacloud-shard-1.  To change a config
file for the cluster, change that file under that directory and then run reload.  From /data/mediacloud:

`script/run_with_carton.sh solr/scripts/reload_solr_shards.pl --num_shards 24 --zk_host localhost --host mcquery1 --host mcquery4`

### Import

The mediacloud account on mcquery2 has the following entry, which runs an hourly incremental import of data into
solr from the main postgres server:

```
35 * * * * time /data/mediacloud/script/run_with_carton.sh /data/mediacloud/script/mediawords_import_solr_data.pl --delta --jobs 8
```

The full import is run by running mediawords_generate_solr_dump.pl on
each of mcquery[124] to generate a set of csvs and then mediawords_import_solr_data.pl on each machine to import those
csvs.  TBD: details of full import.

### Server Configuration

Notes on the configuration of our solr cluster and host machines to avoid OS pitfalls and maximize performance:

#### Conntrack

Add the following lines to sysctl.conf and run sysctl -p to load them.  Solr requires lots of fast, short lived
connections among the solr servers, which hits up against the limits of linux's iptables connection tracking.  This
change greatly increased the number of connections tracked and reduces how long each connection is tracked.

```
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_generic_timeout = 600
net.netfilter.nf_conntrack_tcp_timeout_close = 10
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_established = 600
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 120
net.netfilter.nf_conntrack_tcp_timeout_last_ack = 30
net.netfilter.nf_conntrack_tcp_timeout_max_retrans = 300
net.netfilter.nf_conntrack_tcp_timeout_syn_recv = 60
net.netfilter.nf_conntrack_tcp_timeout_syn_sent = 120
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120
net.netfilter.nf_conntrack_tcp_timeout_unacknowledged = 300
net.netfilter.nf_conntrack_timestamp = 0
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 120
```

#### TCP

Add the following to sysctl.conf and run -p to load.  These are various settings that will optimize kernel handling of
tcp connections between the servers.

`
net.core.wmem_max=12582912
net.core.rmem_max=12582912
net.ipv4.tcp_rmem= 10240 87380 12582912
net.ipv4.tcp_wmem= 10240 87380 12582912
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_no_metrics_save = 1
net.core.netdev_max_backlog = 100000
`

#### Disk Scheduling

Change disk scheduling to 'noop' on all server disks to maximize performance of our RAID arrays:

`
echo noop > /sys/block/hda/queue/scheduler;
echo noop > /sys/block/hdb/queue/scheduler;
`

#### File Limits

Solr can open many files (including sockets), so the default limit of 1024 is insufficient.  Change file
limits by adding to /etc/security/limits.conf:"

`
mediacloud soft nofile 1048576
mediacloud hard nofile 1048576
`

then adding this line to /etc/pam.d/common-session:

`
session required pam_limits.so
`

After making these changes, you need to log back into a new shell session as mediacloud to have access
to the new limits.

#### Round Robin Solr Import

To make imports on the mcquery* machines use all servers equally, add the following lines to mediacloud/mediawords.yml
on each server:

```yml
solr_url:
    - http://localhost:7983/solr
    - http://localhost:7984/solr
    - http://localhost:7985/solr
    - http://localhost:7986/solr
    - http://localhost:7987/solr
    - http://localhost:7988/solr
```

Even though much of the indexing load is distributed naturally to the shard hosting each document, the shard
receiving each import request does a dispropotionate amount of work, so the above further distributes the load.

#### Firewall

Check ufw settings to make sure that the firewall allows all connections between all mcquer* hosts.

#### solrconfig.xml

Check for the following settings in mediacloud/solr/collection1/conf/solrconfig.xml to make sure we are allocating
enough resources to the indexing process:

```xml
<maxIndexingThreads>24</maxIndexingThreads>

   <ramBufferSizeMB>5000</ramBufferSizeMB>
   <maxBufferedDocs>500000</maxBufferedDocs>
```

Also, make sure that the various caches are not too large.  Each cache entry is an entire resultset, and some searches
on our data can return millions or billions of document ids, which can quickly eat up even our large heap.
