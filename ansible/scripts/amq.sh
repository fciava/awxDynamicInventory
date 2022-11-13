install_preliminary_packages (){
  echo "Installing first set packages"
  echo
  yum update -y -q
  timedatectl set-timezone Europe/Rome
  yum -q install -y mlocate ksh.x86_64 net-tools dos2unix.x86_64
  echo "Installing second set packages"
  echo
  yum -q install -y zip unzip telnet
  echo "Installing third set packages"
  echo
  yum -q install -y sysstat.x86_64
  echo "Installing aws cli"
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  ./aws/install
  rm awscliv2.zip
  echo "Ending function"
  echo
}

download_packages () {
  echo "Creating temporary folder"
  echo
  mkdir -p /opt/tmp
  chown -R ec2-user:ec2-user /opt/tmp
  echo "Downloading packages in /opt/tmp"
  echo
  /usr/local/bin/aws s3 cp --only-show-errors --recursive "s3://cadit-pipelines-collaudo/installer/" /opt/tmp --region eu-south-1
  echo "Ending function"
  echo
}

cadit_software_install_amq () {
  echo "Inserting cadgroup group"
  echo
  groupadd -g 502 cadgroup
  echo "Adding user iccreaaf"
  echo
  mkdir -p /opt/iccreaaf/home
  useradd -g cadgroup -d /opt/iccreaaf/home iccreaaf
  chown iccreaaf:cadgroup /opt/iccreaaf/home
  echo "Adding password"
  echo
  su <<EOF
echo iccreaaf | passwd iccreaaf --stdin
EOF

  echo "Creating cadit profile"
  echo
  cadit_profile=$\
'#CADIT#
JAVA_HOME=/opt/java/openjdk-11
export JAVA_HOME

PATH=$PATH:$HOME/.local/bin:$HOME/bin:$JAVA_HOME/bin
export PATH
umask 0002'
  echo "Entering iccreaaf"
  echo
  su - iccreaaf <<HERE
echo "Writing profile in .bash_profile"
echo
echo "$cadit_profile" | tee -a ~/.bash_profile >/dev/null;
HERE
}

# 2.1.2
amq_installation () {
  su - <<EOF
echo "Creating /opt/amq"
echo
mkdir /opt/amq
echo "Entering /opt/amq"
echo
cd /opt/amq
echo "Extracting Redhat AMQ"
echo
unzip -q /opt/tmp/1_impianto/amq/software/amq-broker-7.8.1-bin.zip -d /opt/amq
echo "Creating symbolic link"
echo
ln -s amq-broker-7.8.1/ amq-broker

echo "Going to /opt/iccreaaf"
echo
cd /opt/iccreaaf
echo "Creating AMQ master and slave directories"
echo

#new perché non vada col new line questo non lo so
mkdir -p amq \
amq/bin \
amq/etc \
amq/log \
amq/tmp \
amq/tmp/webapps \
amq/lib \
amq/data \
amq/data/paging \
amq/data/journal \
amq/data/bindings \
amq/data/large-messages \
amq/lock

echo "Copying JDBC driver"
echo
cp /opt/tmp/2_applicazione/jboss/modules/org/postgresql/main/postgresql-42.2.6-jre8.jar \
  /opt/amq/amq-broker/lib/

echo "Going to /opt/iccreaaf/amq"
echo
cd /opt/iccreaaf/amq
echo "Creating AMQ instance"
echo


/opt/amq/amq-broker/bin/artemis create --clustered --cluster-user "admin" \
  --cluster-password "password" --failover-on-shutdown \
  --home "/opt/amq/amq-broker" --default-port 61616 --jdbc \
  --jdbc-bindings-table-name "AMQ_BNDGS"\
  --jdbc-large-message-table-name "AMQ_LMSG"\
  --jdbc-message-table-name "AMQ_MSG"\
  --jdbc-node-manager-table-name "AMQ_NMGR"\
  --jdbc-page-store-table-name "AMQ_PGST"\
  --name "amq" --user "admin" --password "password"\
  --shared-store --staticCluster 'tcp://$hostname_address:61616' \
  --host "guerro" \
  --require-login  --no-hornetq-acceptor --no-mqtt-acceptor --no-stomp-acceptor\
  --no-amqp-acceptor /opt/iccreaaf/amq 

#nello user data

echo "Changing permissions to amq folder"
echo
chown -R iccreaaf:cadgroup /opt/iccreaaf/amq/

echo "Copying master files"
echo

yes | cp -r /opt/tmp/2_applicazione/amq \
  /opt/iccreaaf/

chmod +x /opt/iccreaaf/amq/bin/artemis


EOF

  cd /opt/iccreaaf/amq/etc
  sed -i 's/$dbname/cadiccreaaf/g' broker.xml
  sed -i 's/$dbport/5432/g' broker.xml
  sed -i 's/$dbusr/caddb/g' broker.xml
  sed -i "s/\$dbpsw/$db_passwd/g" broker.xml

  echo "Exiting function"
  echo
}


amq_service_create () {
  echo "Writing AMQ service"
  echo
  amq_service=$\
'[Unit]
Description=Redhat AMQ
After=network.target

[Service]
Type=Simple
User  = iccreaaf
Group = cadgroup
TimeoutStartSec = 30
TimeoutStopSec  = 30
ExecStart = /opt/iccreaaf/amq/bin/artemis run
ExecStop  = /opt/iccreaaf/amq/bin/artemis stop
Restart=on-abort

LimitNOFILE=102642

[Install]
WantedBy=multi-user.target'


  amq_service_path='/usr/lib/systemd/system/'
  echo "Creating AMQ service file"
  echo
  echo "$amq_service" > amq-iccreaaf.service
  #chmod 744 amq-iccreaaf.service
  cp amq-iccreaaf.service $amq_service_path
  rm -r amq-iccreaaf.service

  echo "Reloading, enabling, starting AMQ services"
  echo
  systemctl daemon-reload
  systemctl enable amq-iccreaaf.service

  echo "Writing AMQ initd service"
  echo
  
  amq_initd_service=$\
'### BEGIN INIT INFO
# Provides: amq-iccreaaf
# Required-Start: $network
# Required-Stop:
# Default-Start:
# Default-Stop:
# Description:  Redhat AMQ
### END INIT INFO

SERVICENAME=amq-iccreaaf.service

usage ()
{
        echo -e "$0 <start|stop|status|restart>"
        echo -e ""
}

case "$1" in
   start  )
        systemctl start $SERVICENAME
        ;;
   stop   )
        systemctl stop $SERVICENAME
        ;;
   status )
        systemctl status $SERVICENAME
        ;;
   restart)
        systemctl restart $SERVICENAME
        ;;
   *    )
        usage
        exit 1
        ;;
esac'

  amq_initd_path='/etc/init.d/'
  echo "Writing AMQ initd file"
  echo
  echo "$amq_initd_service" > amq-iccreaaf
  cp amq-iccreaaf $amq_initd_path
  rm -r amq-iccreaaf



  echo "Change permissions to 754 to the AMQ initd service"
  echo
  chmod 754 $amq_initd_path/amq-iccreaaf

  echo "Exiting function"
  echo
}


function error_exit {
    echo
    echo "$@"
    exit 1
}
#Trap the killer signals so that we can exit with a good message.
trap "error_exit 'Received signal SIGHUP'" SIGHUP
trap "error_exit 'Received signal SIGINT'" SIGINT
trap "error_exit 'Received signal SIGTERM'" SIGTERM

#Alias the function so that it will print a message with the following format:
#prog-name(@line#): message
#We have to explicitly allow aliases, we do this because they make calling the
#function much easier (see example).
shopt -s expand_aliases
alias die='error_exit "Error ${0}(@`echo $(( $LINENO - 1 ))`):"'
############################################################################

install_preliminary_packages || die "Error in installing packages" #Pacchetto java-11-openjdk-devel.x86_64 disponibile
download_packages || die "Error in retrieving data from S3"
cadit_software_install_amq || die "Error installing cadit software in AMQ machine"
amq_installation || die "Error in installing AMQ"
amq_service_create  || die "Error in creating AMQ service"