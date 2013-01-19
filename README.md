Mongo Shardgen
==============
This is a tiny script to create a set of MongoDB shards and replica sets. Just edit `settings.conf` to your needs and run `create-mongo.sh`

You can perform as well a remote deployment via SSH using `deploy-mongo.sh`

Most likely you will have to change following values:

* Config-Server name pattern (CONFIG_SERVER_SCHEME)
* Shard-Server name pattern (SHARD_SERVER_SCHEME)
* Number of shards/server (SHARD_COUNT_PER_SERVER)
* Number of replica sets (REPLICA_SET_COUNT)
* Your data/instance base directory (BASEDIR)
* The Mongo binaries directory (MONGO_BIN)
* Your SSH deployment user (DEPLOY_SSH_USER)

Following artifacts are produced in the `output` directory:

* Directory-structore per server, containing an instance directory with conf-file and a set of scripts to start/stop
* The cluster key-file (shard/replica authentication)
* finalize-install.sh (post-deployment script, run it as root to install LSB-compliant init.d scripts and move the server config on the approriate server in its base-dir)
* setup-replica.sh script to setup replication
* setup-shards.sh for sharding

Feel free to contribute. Especially the setup-replica.sh scripts raise errors since they try to add shards/replicas multiple times. It's not a real problem, since MongoDB adds all shards of a replica to a sharded cluster, but it's not nice.

*Please note: This script does not download the MongoDB binaries. It creates only a set of config/deployment files*