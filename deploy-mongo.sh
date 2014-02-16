#/bin/bash
# Author: Mark Paluch <mpaluch@paluch.biz>

if [ ! -e "settings.conf" ] ; then
	echo "Missing settings.conf"
	exit 1
fi

. settings.conf


THE_CONFIG_SERVERS=$(eval echo "$CONFIG_SERVER_SCHEME")
THE_SHARD_SERVERS=$(eval echo "$SHARD_SERVER_SCHEME")
OUTPUT_PATH=output

MONGO_CONFIG_DIR=mongodb
MONGO_SHARD_DIR=mongodb

for (( rs=1; rs<=$REPLICA_SET_COUNT; rs++ ))
do
	for server in $THE_SHARD_SERVERS
	do
		ssh $@ ${DEPLOY_SSH_USER}@${server} "rm -Rf $MONGO_CONFIG_DIR"
	done
done

for server in $THE_CONFIG_SERVERS
do
	ssh $@ ${DEPLOY_SSH_USER}@${server} "rm -Rf $MONGO_CONFIG_DIR"
done

for server in $THE_CONFIG_SERVERS
do
	echo "Config-Server: $server"
	SERVER_PATH=$OUTPUT_PATH/${server}
	INSTANCE=mongod-config
	INSTANCE_PATH=$SERVER_PATH/$INSTANCE
	
	ssh $@ ${DEPLOY_SSH_USER}@${server} "mkdir -p $MONGO_CONFIG_DIR && mkdir -p $MONGO_CONFIG_DIR/init.d && mkdir -p $MONGO_CONFIG_DIR/$INSTANCE/data && mkdir -p $MONGO_CONFIG_DIR/logs && mkdir -p $MONGO_CONFIG_DIR/mongos-config"
	
	scp $@ $OUTPUT_PATH/cluster.key ${DEPLOY_SSH_USER}@${server}:$MONGO_CONFIG_DIR/
	scp $@ $SERVER_PATH/start-config-server.sh ${DEPLOY_SSH_USER}@${server}:$MONGO_CONFIG_DIR/
	scp $@ $SERVER_PATH/stop-server.sh ${DEPLOY_SSH_USER}@${server}:$MONGO_CONFIG_DIR/
	scp $@ $INSTANCE_PATH/mongod.conf ${DEPLOY_SSH_USER}@${server}:$MONGO_CONFIG_DIR/$INSTANCE
	scp $@ $SERVER_PATH/mongos-config/mongos.conf ${DEPLOY_SSH_USER}@${server}:$MONGO_CONFIG_DIR/mongos-config
	scp $@ init.d-debian/mongod ${DEPLOY_SSH_USER}@${server}:$MONGO_CONFIG_DIR/init.d/
	scp $@ init.d-debian/mongos ${DEPLOY_SSH_USER}@${server}:$MONGO_CONFIG_DIR/init.d/
	scp $@ $OUTPUT_PATH/finalize-install.sh ${DEPLOY_SSH_USER}@${server}:$MONGO_SHARD_DIR/
	scp $@ $SERVER_PATH/start-all-init.sh ${DEPLOY_SSH_USER}@${server}:$MONGO_SHARD_DIR/
	scp $@ $SERVER_PATH/stop-all-init.sh ${DEPLOY_SSH_USER}@${server}:$MONGO_SHARD_DIR/
	
	scp $@ $OUTPUT_PATH/*.sh ${DEPLOY_SSH_USER}@${server}:$MONGO_CONFIG_DIR
	
	ssh $@ ${DEPLOY_SSH_USER}@${server} "cd $MONGO_CONFIG_DIR/init.d && ln -s mongod $INSTANCE  && ln -s mongos mongos-config"
	ssh $@ ${DEPLOY_SSH_USER}@${server} "chmod -R go-rwx $MONGO_CONFIG_DIR && chmod a+x $MONGO_CONFIG_DIR/*.sh && chmod a+x $MONGO_CONFIG_DIR/init.d"
done

for (( rs=1; rs<=$REPLICA_SET_COUNT; rs++ ))
do
	for server in $THE_SHARD_SERVERS
	do
		server=$(eval echo "$server")
		echo "Shard-Server: $server"
		SERVER_PATH=$OUTPUT_PATH/${server}
		ssh $@ ${DEPLOY_SSH_USER}@${server} "mkdir -p $MONGO_SHARD_DIR/init.d"
	
		scp $@ init.d-debian/mongod ${DEPLOY_SSH_USER}@${server}:$MONGO_SHARD_DIR/init.d/
	
		for (( c=1; c<=$SHARD_COUNT_PER_SERVER; c++ ))
		do
			SHARD_PORT=$(expr $SHARD_SERVER_PORT_START + $c)
			REPLSET=${REPLSET_PREFIX}${rs}
			echo "Shard-Server: $server/$REPLSET"
			INSTANCE=mongod-$REPLSET
			INSTANCE_PATH=$SERVER_PATH/$INSTANCE
	
			ssh $@ ${DEPLOY_SSH_USER}@${server} "mkdir -p $MONGO_SHARD_DIR/$INSTANCE/data && mkdir -p $MONGO_SHARD_DIR/$INSTANCE/logs && cd $MONGO_SHARD_DIR/init.d && ln -s mongod $INSTANCE"
			scp $@ $INSTANCE_PATH/*.conf ${DEPLOY_SSH_USER}@${server}:$MONGO_SHARD_DIR/$INSTANCE
		done
	
		scp $@ $SERVER_PATH/start-shard-server.sh ${DEPLOY_SSH_USER}@${server}:$MONGO_SHARD_DIR/
		scp $@ $SERVER_PATH/stop-server.sh ${DEPLOY_SSH_USER}@${server}:$MONGO_SHARD_DIR/
		scp $@ $SERVER_PATH/start-all.sh ${DEPLOY_SSH_USER}@${server}:$MONGO_SHARD_DIR/
		scp $@ $SERVER_PATH/start-all-init.sh ${DEPLOY_SSH_USER}@${server}:$MONGO_SHARD_DIR/
		scp $@ $SERVER_PATH/stop-all-init.sh ${DEPLOY_SSH_USER}@${server}:$MONGO_SHARD_DIR/
		scp $@ $OUTPUT_PATH/finalize-install.sh ${DEPLOY_SSH_USER}@${server}:$MONGO_SHARD_DIR/

		scp $@ $OUTPUT_PATH/cluster.key ${DEPLOY_SSH_USER}@${server}:$MONGO_SHARD_DIR/

		ssh $@ ${DEPLOY_SSH_USER}@${server} "chmod -R go-rwx $MONGO_SHARD_DIR && chmod a+x $MONGO_SHARD_DIR/*.sh && chmod a+x $MONGO_CONFIG_DIR/init.d"
	done
done
