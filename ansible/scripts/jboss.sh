#!/bin/bash

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
  # echo "Installing aws cli"
  # curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  # unzip -q awscliv2.zip
  # ./aws/install
  # rm awscliv2.zip
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

jdk_install () {
  echo "Creating folder Java"
  echo
  mkdir -p /opt/java
  echo "Creating symbolic link with Java JDK folder"
  echo
  dir=$(ls -d /usr/lib/jvm/java-11-openjdk-*/)
  ln -s $dir /opt/java/openjdk-11
  echo "Ending function"
  echo
}

jboss_install () {
  echo "Creating JBoss folder"
  echo
  mkdir -p /opt/jboss
  #mv /opt/tmp/jboss-eap-7.2.0.zip /opt/jboss
  echo "Entering JBoss folder"
  echo
  cd /opt/jboss
  echo "Extraction from .zip archive"
  echo
  unzip -uq /opt/tmp/jboss-eap-7.2.0.zip -d /opt/jboss
  rm -Rf /opt/tmp/jboss-eap-7.2.0.zip # clear space
  echo "Ending function"
  echo
}

jboss_service_create () {
  echo "Writing JBoss service"
  echo
  jboss_service=$\
'[Unit]
Description=Jboss BPS EA
After=network.target

[Service]
Type=forking
TimeoutStartSec = 300
TimeoutStopSec  = 300
PIDFile   = /opt/iccreaaf/frontend/jboss/af/run/jboss-eap.pid
ExecStart = /opt/iccreaaf/etc/init.d/jboss-iccreaaf start
ExecStop  = /opt/iccreaaf/etc/init.d/jboss-iccreaaf stop
Restart=on-abort

LimitNOFILE=102642

[Install]
WantedBy=multi-user.target'

  echo "Writing path JBoss service"
  echo
  #jboss_service_path='/usr/lib/systemd/system/jboss-iccreaaf.service'
  jboss_service_path='/usr/lib/systemd/system/'
  echo "Creating JBoss service file"
  echo
  #echo "$jboss_service" >> $jboss_service_path
  echo "$jboss_service" >> jboss-iccreaaf.service
  chmod 744 jboss-iccreaaf.service
  cp jboss-iccreaaf.service $jboss_service_path
  rm -r jboss-iccreaaf.service
  echo "Reloading daemons"
  echo
  systemctl daemon-reload
  echo "Enabling JBoss service"
  echo
  systemctl enable jboss-iccreaaf.service
  echo "Writing JBoss initd service"
  echo
  jboss_initd_service=$\
'### BEGIN INIT INFO
# Provides: jboss-iccreaaf
# Required-Start: $network
# Required-Stop:
# Default-Start:
# Default-Stop: 0 1 6
# Description:  Jboss
### END INIT INFO
SERVICENAME=jboss-iccreaaf.service

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
  echo "Writing JBoss initd path"
  echo
  #jboss_initd_path="/etc/init.d/jboss-iccreaaf"
  jboss_initd_path='/etc/init.d/'
  echo "Writing JBoss initd file"
  echo
  echo "$jboss_initd_service" > jboss-iccreaaf
  cp jboss-iccreaaf $jboss_initd_path
  echo "Change permissions to 754 to the JBoss initd path"
  echo
  chmod 754 $jboss_initd_path/jboss-iccreaaf
  rm -r jboss-iccreaaf
  echo "Exiting function"
  echo
}

cadit_software_install () {
  echo "Inserting cadgroup group"
  echo
  groupadd -f -g 502 cadgroup
  echo "Adding user iccreaaf"
  echo
  mkdir -p /opt/iccreaaf/home
  id -u iccreaaf &>/dev/null || useradd -g cadgroup -d /opt/iccreaaf/home iccreaaf
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
echo "$cadit_profile" | tee ~/.bash_profile >/dev/null;
HERE
  echo "Creating directories"
  echo
  mkdir -p /opt/iccreaaf/cache/af
  mkdir -p /opt/iccreaaf/frontend/jboss/af
  mkdir -p /opt/iccreaaf/frontend/jboss/af/external-modules
  mkdir -p /opt/iccreaaf/frontend/jboss/af/log
  mkdir -p /opt/iccreaaf/frontend/jboss/af/standalone
  mkdir -p /opt/iccreaaf/frontend/jboss/af/run

  echo "Copying jboss standalone folder in iccreaaf"
  echo
  cp -dRf /opt/jboss/jboss-eap-7.2/standalone/* \
        /opt/iccreaaf/frontend/jboss/af/standalone/
  echo "Change permissions"
  echo

  echo "Creating folder /opt/iccreaaf/etc/init.d"
  echo
  mkdir -p /opt/iccreaaf/etc/init.d
  echo "Copying folder jboss-iccreaaf"
  echo
  cp -rf /opt/tmp/1_impianto/jboss/opt/iccreaaf/etc/init.d/jboss-iccreaaf \
        /opt/iccreaaf/etc/init.d
  rm -Rf /opt/tmp/1_impianto/jboss/opt/iccreaaf/etc/init.d/jboss-iccreaaf # clear space     
  echo "Change permissions jboss-iccreaaf"
  echo
  #NEW
  chown -R iccreaaf:cadgroup /opt/iccreaaf/*
  chmod -R 770 /opt/iccreaaf/frontend/*
  chown root:root /opt/iccreaaf/etc/init.d/jboss-iccreaaf
  chmod 775 /opt/iccreaaf/etc/init.d/jboss-iccreaaf

  # Adding Change permissions --> NON FUNZIONANO(?)
  chmod -R 754 /opt/iccreaaf/etc/init.d/*
  chmod -R 754 /etc/init.d/*

  echo "Copying folder jacobBatchClient"
  echo
  # cp -r /opt/tmp/1_impianto/jacob-batch-client/jacobBatchClient \
  #       /opt/iccreaaf/backend/sys/
  #echo "Executing cadjob"
  #echo
  #/opt/iccreaaf/backend/sys/jacobBatchClient/cadjob sijb04 si
  echo "Ending function"
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
jdk_install || die "Error in installing JDK"
# download_packages || die "Error in downloading packages"
jboss_install || die "Error in installing JBoss"
jboss_service_create || die "Error in creating JBoss service"
cadit_software_install || die "Error in installing CADIT"