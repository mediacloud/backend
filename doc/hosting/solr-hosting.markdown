# Solr Hosting


## Generic Information

SolrCloud requires a fair amount of hand holding to get all of the shards (individual cluster server instances) running together happily.  The basic idea is that you run a single instance of ZooKeeper which manages all the Solr shards, and then make Solr shards attach to said ZooKeeper instance.  There is no single Solr command to create or start an entire cluster of shards.

To simplify cluster creation, startup, and configuration reloads, we have some local scripts that manage these tasks.

All of these scripts live under `tools/solr/run/` and support `-h` parameter to provide some rudimentary help.


## Standalone Instance

**`run_solr_standalone.py` - run standalone Solr instance.**

Usage:

	./run_solr_standalone.py

Sets up and starts a standalone Solr instance on 8983 port, e.g. to be used for development or testing. Instance's data is stored under `data/solr/mediacloud-standalone/`.

It is possible to start / stop standalone Solr instance using Supervisor.


## Cluster


### Start ZooKeeper

**`run_zookeeper.py` - start ZooKeeper instance to manage Solr shards.**

Usage:

	./run_zookeeper.py

Sets up and starts a ZooKeeper instance on 9983 port. (Re)uploads Solr configuration on every startup.

It is advisable to start / stop ZooKeeper using Supervisor.


### Start Shard(s)

**`run_solr_shard.py` -- start a specified Solr shard.**

Usage:

	./run_solr_shard.py \
		--shard_num 1 \
		--shard_count 8 \
		[--zookeeper_host localhost] \
		[--zookeeper_port 9983]
	
	./run_solr_shard.py \
		--shard_num 2 \
		--shard_count 8 \
		...

	./run_solr_shard.py \
		--shard_num 3 \
		--shard_count 8 \
		...
	
	...

Sets up and starts a Solr shard on port starting with 7981 (i.e. shard 1 will start on port 7981, shard 2 will start on port 7981, etc.) Instance's data is stored under `data/solr/mediacloud-mediacloud-cluster-shard-[shard_num]/`. You must also specify the total number of shards across the cluster that you intend to run.

It is advisable to configure a number of shards in `mediawords.yml` and start / stop Solr shards using Supervisor.


### Update Solr's configuration

**`update_zookeeper_config.py` - upload Solr configuration to ZooKeeper instance.**

Usage:

	./update_zookeeper_config.py \
		[--zookeeper_host localhost] \
		[--zookeeper_port 9983]

Updates current Solr configuration on ZooKeeper (this is also done every time ZooKeeper is started). Does not reload Solr shards itself (`reload_solr_shards.py` does that).

### Reload Solr shards

**`reload_solr_shards.py` - reload Solr shard(s) after updating configuration on ZooKeeper.**

Usage:

	./reload_solr_shards.py \
		--shard_count 8 \
		[--host host_with_solr_shards_1] \
		[--host host_with_solr_shards_2] \
		[--host host_with_solr_shards_3] \
		...

After configuration update on ZooKeeper, reloads all Solr shards with the new configuration on specified host(s) running those shards. Does not upload Solr configuration to ZooKeeper itself (`update_zookeeper_config.py` does that).

After reloading the configuration, you can connect to the individual shards (for instance <http://localhost:7981/solr/>) and load
the configuration page to verify that a given configuration change has made it into the running shard.


## Tools


### Upgrade Lucene indexes

**`upgrade_lucene_index.py` - upgrade Lucene index before moving between major Solr versions**

Usage:

	./upgrade_lucene_index.py --standalone
	# or
	./upgrade_lucene_index.py --cluster

After upgrading between major Solr versions (e.g. Solr 5 to Solr 6), you must run [`IndexUpgrader` tool](https://cwiki.apache.org/confluence/display/solr/IndexUpgrader+Tool) to upgrade Lucene indexes too. This tool will run the index upgrade to either a standalone Solr instance or all Solr shards residing in the data directory.


### Optimize indexes

**`optimize_solr_index.py` - optimize Solr indexes of one, multiple or all collections.**

Usage:

	./optimize_solr_index.py \
		[--host localhost ] \
		[--port 7931] \
		[--collection collection1 --collection collection2 ...]

It is recommended to recreate indexes after upgrading Solr to make use of new (potentially optimized) indexing algorithm.


## MIT Specific Instructions

The Solr installation consists of four machines -- `mcquery[1234]`.  We run the Solr cluster on three of those machines and keep the fourth machine as a cold spare.  Each of the machines is a nearly identical Dell rack server with 16 cores and 192G RAM.  `[234]` have a 360G RAID1'd system disk.  `[1]` has a slower 600G RAID1'd system disk.  All four members of the array run Solr on an SSD array mounted on `/data`.  The SSD array runs on 4 RAID10'd 500G SSDs.

We run a cluster of 24 shards, with each active server running 8 shards.  Most of Solr's parallel capacity comes from the individual shards rather than from threading on an individual shard, so we need lots of shards to take advantage of all of our cores.

We are currently running our cluster in `mcquery[124]`.  `mcquery3` corrupted some data during the last full import, and we need to do a diagnosis to figure out if there's something goofy before using the machine again.

`mcquery2` runs the ZooKeeper instance.  `mcquery2` is also the machine that runs the hourly import script, even though we could run the import on any of the shards.

The Media Cloud installation on each of these machines is under `/data/mediacloud`.  Solr is in `/data/mediacloud/solr`.

Each server has a full Media Cloud install, with the configuration pointing to `localhost:6001` as the PostgreSQL port.  There should be an SSH process tunneling 6001 to PostgreSQL on the production database (currently `mcdb1`).

The only thing the Media Cloud install is used for on these machines (other than the Solr installation) is the import process.  `mcquery2` runs the hourly import script.  The other cluster machines only need to run an import when doing a full import (just to speed up the process).


### Import

The `mediacloud` account on `mcquery2` has the following entry, which runs an hourly incremental import of data into Solr from the main PostgreSQL server:

	35 * * * * time /data/mediacloud/script/run_with_carton.sh /data/mediacloud/script/mediawords_import_solr_data.pl --delta --jobs 8

The full import is run by running `mediawords_generate_solr_dump.pl` on each of `mcquery[124]` to generate a set of CSVs and then `mediawords_import_solr_data.pl` on each machine to import those csvs.  TBD: details of full import.


### Server Configuration

Notes on the configuration of our Solr cluster and host machines to avoid OS pitfalls and maximize performance:


#### Conntrack

Add the following lines to `sysctl.conf` and run `sysctl -p` to load them.  Solr requires lots of fast, short lived connections among the Solr servers, which hits up against the limits of Linux's *iptables* connection tracking.  This change greatly increased the number of connections tracked and reduces how long each connection is tracked.

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


#### TCP

Add the following to `sysctl.conf` and run `-p` to load.  These are various settings that will optimize kernel handling of tcp connections between the servers.

	net.core.wmem_max=12582912
	net.core.rmem_max=12582912
	net.ipv4.tcp_rmem= 10240 87380 12582912
	net.ipv4.tcp_wmem= 10240 87380 12582912
	net.ipv4.tcp_window_scaling = 1
	net.ipv4.tcp_timestamps = 1
	net.ipv4.tcp_sack = 1
	net.ipv4.tcp_no_metrics_save = 1
	net.core.netdev_max_backlog = 100000


#### Disk Scheduling

Change disk scheduling to `noop` on all server disks to maximize performance of our RAID arrays:

	echo noop > /sys/block/hda/queue/scheduler;
	echo noop > /sys/block/hdb/queue/scheduler;


#### File Limits

Solr can open many files (including sockets), so the default limit of 1024 is insufficient.  Change file limits by adding to `/etc/security/limits.conf`:

	mediacloud soft nofile 1048576
	mediacloud hard nofile 1048576

then adding this line to `/etc/pam.d/common-session`:

	session required pam_limits.so

After making these changes, you need to log back into a new shell session as `mediacloud` to have access to the new limits.

#### Round Robin Solr Import

To make imports on the `mcquery*` machines use all servers equally, add the following lines to `mediacloud` section in `mediawords.yml` on each server:

	solr_url:
	    - http://localhost:7981/solr
	    - http://localhost:7982/solr
	    - http://localhost:7983/solr
	    - http://localhost:7984/solr
	    - http://localhost:7985/solr
	    - http://localhost:7986/solr
	    - http://localhost:7987/solr
	    - http://localhost:7988/solr

Even though much of the indexing load is distributed naturally to the shard hosting each document, the shard receiving each import request does a dispropotionate amount of work, so the above further distributes the load.

#### Firewall

Check *ufw* settings to make sure that the firewall allows all connections between all `mcquery*` hosts.
