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
CONFIG_TEMPLATE=templates/configserver.template
CONFIG_MONGOS_TEMPLATE=templates/configserver-mongos.template
SHARD_TEMPLATE=templates/shard.template
FINALIZE_TEMPLATE=templates/finalize-install.sh.template

rm -Rf $OUTPUT_PATH/*
mkdir -p $OUTPUT_PATH
openssl rand -base64 $KEY_FILE_LENGTH > $OUTPUT_PATH/cluster.key

CONFIG_SERVERS=""


FIRST_CONFIG_SERVER=""
FIRST_SHARD_SERVER=""

i=1
for (( rs=1; rs<=$REPLICA_SET_COUNT; rs++ ))
do
	for server in $THE_SHARD_SERVERS
	do
		server=$(eval echo "$server")
		for (( c=1; c<=$SHARD_COUNT_PER_SERVER; c++ ))
		do
			SHARD_PORT=$(expr $SHARD_SERVER_PORT_START + $c)
			SHARD_COUNTER=$(expr $i + $c)
					
			if [[ "$REPLICA_SET_COUNT" == "$SHARD_COUNT_PER_SERVER" ]] ; then			
				if [ "$i" == "$c" ] ; then
					echo " echo \"rs.initiate();\" | ${MONGO_BIN}/mongo ${server}:${SHARD_PORT}" >> $OUTPUT_PATH/setup-replicas.sh
				fi
			else
				echo " echo \"rs.initiate();\" | ${MONGO_BIN}/mongo ${server}:${SHARD_PORT}" >> $OUTPUT_PATH/setup-replicas.sh
				break
			fi
		done
		
		if [[ "$REPLICA_SET_COUNT" != "$SHARD_COUNT_PER_SERVER" ]] ; then
			break
		fi
		i=$(expr $i + 1)		
	done
done

echo " echo \"sleep 20\"" >> $OUTPUT_PATH/setup-replicas.sh
echo " sleep 20" >> $OUTPUT_PATH/setup-replicas.sh
i=1
for (( rs=1; rs<=$REPLICA_SET_COUNT; rs++ ))
do
	for server in $THE_SHARD_SERVERS
	do
		server=$(eval echo "$server")
		for (( c=1; c<=$SHARD_COUNT_PER_SERVER; c++ ))
		do
			SHARD_PORT=$(expr $SHARD_SERVER_PORT_START + $c)
			SHARD_COUNTER=$(expr $i + $c)
		
			if [[ "$REPLICA_SET_COUNT" != "$SHARD_COUNT_PER_SERVER" ]] || [[ "$i" == "$c" ]] ; then
				for server2 in $THE_SHARD_SERVERS
				do
					server2=$(eval echo "$server2")
 					if [ "$server2" != "$server" ] ; then
						echo " echo \"rs.add(\\\"${server2}:${SHARD_PORT}\\\");\" | ${MONGO_BIN}/mongo ${server}:${SHARD_PORT}" >> $OUTPUT_PATH/setup-replicas.sh
					fi
				done
			fi
		done
	done
	i=$(expr $i + 1)
done

for server in $THE_CONFIG_SERVERS
do
	if [ ! $CONFIG_SERVERS = "" ] ; then
		CONFIG_SERVERS="${CONFIG_SERVERS},"		
	else
		FIRST_CONFIG_SERVER="${server}"
	fi
	
	CONFIG_SERVERS="${CONFIG_SERVERS}${server}"
done


chmod a+x  $OUTPUT_PATH/*.sh

ADD_USER="db.addUser(\\\"$ADMIN_USER_NAME\\\", \\\"$ADMIN_PASSWORD\\\");"
		
echo " echo \"$ADD_USER\" | ${MONGO_BIN}/mongo ${FIRST_CONFIG_SERVER}/admin" >> $OUTPUT_PATH/setup-shards.sh


for server in $THE_CONFIG_SERVERS
do
	SERVER_PATH=$OUTPUT_PATH/$server
	INSTANCE=mongod-config
	INSTANCE_PATH=$SERVER_PATH/$INSTANCE
	mkdir -p $SERVER_PATH/logs
	mkdir -p $INSTANCE_PATH/data
	mkdir -p $SERVER_PATH/mongos-config
	
	cp $OUTPUT_PATH/cluster.key $SERVER_PATH
	chmod go-rwx $SERVER_PATH/cluster.key
		
	echo "${MONGO_BIN}/mongod --quiet --dbpath $BASEDIR/$INSTANCE/data --config $BASEDIR/$INSTANCE/mongod.conf --oplogSize 50" >> $SERVER_PATH/start-config-server.sh
	echo "sleep 1" >> $SERVER_PATH/start-config-server.sh
	echo "${MONGO_BIN}/mongos --quiet --config $BASEDIR/mongos-config/mongos.conf" >> $SERVER_PATH/start-config-server.sh
	
	echo "${MONGO_BIN}/mongod --quiet --dbpath $BASEDIR/$INSTANCE/data --config $BASEDIR/$INSTANCE/mongod.conf --oplogSize 50" >> $SERVER_PATH/start-all.sh
	echo "sleep 1" >> $SERVER_PATH/start-all.sh
	echo "${MONGO_BIN}/mongos --quiet --config $BASEDIR/mongos-config/mongos.conf" >> $SERVER_PATH/start-all.sh

	echo "/etc/init.d/${INSTANCE} start" >> $SERVER_PATH/start-all-init.sh
	echo "/etc/init.d/${INSTANCE} stop" >> $SERVER_PATH/stop-all-init.sh

	echo "/etc/init.d/mongos-config start" >> $SERVER_PATH/start-all-init.sh
	echo "/etc/init.d/mongos-config stop" >> $SERVER_PATH/stop-all-init.sh
	
	eval "cat <<< \"$(<$CONFIG_TEMPLATE)\"" 2> /dev/null > $INSTANCE_PATH/mongod.conf
	eval "cat <<< \"$(<$CONFIG_MONGOS_TEMPLATE)\"" 2> /dev/null > $SERVER_PATH/mongos-config/mongos.conf
	
	chmod a+x  $SERVER_PATH/*.sh
	
done

for (( rs=1; rs<=$REPLICA_SET_COUNT; rs++ ))
do
	for server in $THE_SHARD_SERVERS
	do
		server=$(eval echo "$server")
		SERVER_PATH=$OUTPUT_PATH/$server
		mkdir -p $SERVER_PATH/logs
		mkdir -p $INSTANCE_PATH/data
	
		cp $OUTPUT_PATH/cluster.key $SERVER_PATH
		chmod go-rwx $SERVER_PATH/cluster.key	
	
		for (( c=1; c<=$SHARD_COUNT_PER_SERVER; c++ ))
		do
			SHARD_PORT=$(expr $SHARD_SERVER_PORT_START + $c)
			REPLSET=${REPLSET_PREFIX}${rs}
			INSTANCE=mongod-$REPLSET
			INSTANCE_PATH=$SERVER_PATH/$INSTANCE
			mkdir -p $INSTANCE_PATH
			
			if [[ -f "$SERVER_PATH/start-shard-server.sh" ]] && [[ "" != "$(grep $INSTANCE $SERVER_PATH/start-shard-server.sh)" ]] ; then
				continue
			fi
			
			echo "${MONGO_BIN}/mongod --dbpath $BASEDIR/$INSTANCE/data --config $BASEDIR/$INSTANCE/mongod.conf --oplogSize 50" >> $SERVER_PATH/start-shard-server.sh
			echo "${MONGO_BIN}/mongod --dbpath $BASEDIR/$INSTANCE/data --config $BASEDIR/$INSTANCE/mongod.conf --oplogSize 50" >> $SERVER_PATH/start-all.sh
		
			echo "/etc/init.d/${INSTANCE} start" >> $SERVER_PATH/start-all-init.sh
			echo "/etc/init.d/${INSTANCE} stop" >> $SERVER_PATH/stop-all-init.sh
		
			ADD_SHARD_CMD="db.runCommand({addShard:\\\"$REPLSET/${server}:${SHARD_PORT}\\\", name: \\\"shard-$REPLSET\\\"});"
		
			echo " echo \" $ADD_SHARD_CMD \" | ${MONGO_BIN}/mongo ${FIRST_CONFIG_SERVER}/admin" >> $OUTPUT_PATH/setup-shards.sh
			eval "cat <<< \"$(<$SHARD_TEMPLATE)\"" 2> /dev/null > $INSTANCE_PATH/mongod.conf
				
		done
	
		echo "tail -f $BASEDIR/logs/*" >> $SERVER_PATH/start-all.sh
	
		echo "pkill mongod" > $SERVER_PATH/stop-server.sh
		echo "pkill mongos" >> $SERVER_PATH/stop-server.sh	
		chmod a+x  $SERVER_PATH/*.sh
	done
done

eval "cat <<< \"$(<$FINALIZE_TEMPLATE)\"" 2> /dev/null > $OUTPUT_PATH/finalize-install.sh
