#!/bin/bash

echo $(date) " - Starting Script"

set -e

SUDOUSER=$1
PASSWORD=$2
PRIVATEKEY=$3
MASTER=$4
MASTERPUBLICIPHOSTNAME=$5
MASTERPUBLICIPADDRESS=$6
INFRA=$7
NODE=$8
NODECOUNT=$9
ROUTING=${10}

# Debug
(
echo "SUDOUSER=$SUDOUSER"
echo "PASSWORD=$PASSWORD"
echo "PRIVATEKEY=$PRIVATEKEY"
echo "MASTER=$MASTER"
echo "MASTERPUBLICIPHOSTNAME=$MASTERPUBLICIPHOSTNAME"
echo "MASTERPUBLICIPADDRESS=$MASTERPUBLICIPADDRESS"
echo "INFRA=$INFRA"
echo "NODE=$NODE"
echo "NODECOUNT=$NODECOUNT"
echo "ROUTING=$ROUTING"
) >>/tmp/debug

# DOMAIN=$( awk 'NR==2' /etc/resolv.conf | awk '{ print $2 }' )

echo $PASSWORD

# Generate private keys for use by Ansible
echo $(date) " - Generating Private keys for use by Ansible for OpenShift Installation"

echo "Generating keys"

runuser -l $SUDOUSER -c "echo \"$PRIVATEKEY\" > ~/.ssh/id_rsa"
runuser -l $SUDOUSER -c "chmod 600 ~/.ssh/id_rsa*"

echo "Configuring SSH ControlPath to use shorter path name"

sed -i -e "s/^# control_path = %(directory)s\/%%h-%%r/control_path = %(directory)s\/%%h-%%r/" /etc/ansible/ansible.cfg
sed -i -e "s/^#host_key_checking = False/host_key_checking = False/" /etc/ansible/ansible.cfg
sed -i -e "s/^#pty=False/pty=False/" /etc/ansible/ansible.cfg

# Create Ansible Hosts File
echo $(date) " - Create Ansible Hosts file"

cat > /etc/ansible/hosts <<EOF
# Create an OSEv3 group that contains the masters and nodes groups
[OSEv3:children]
masters
nodes
etcd

# Set variables common for all OSEv3 hosts
[OSEv3:vars]
ansible_ssh_user=$SUDOUSER
ansible_become=yes
openshift_install_examples=true
deployment_type=openshift-enterprise
docker_udev_workaround=True
openshift_use_dnsmasq=no
openshift_master_default_subdomain=$ROUTING

# default selectors for router and registry services 
openshift_router_selector='region=infra' 
openshift_registry_selector='region=infra' 

openshift_master_cluster_method=native
openshift_master_cluster_hostname=$MASTERPUBLICIPHOSTNAME
openshift_master_cluster_public_hostname=$MASTERPUBLICIPHOSTNAME
openshift_master_cluster_public_vip=$MASTERPUBLICIPADDRESS

# Enable HTPasswdPasswordIdentityProvider
openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider', 'filename': '/etc/origin/master/htpasswd'}]

# Enable cockpit
osm_use_cockpit=true

# host group for masters
[masters]
$MASTER openshift_node_labels="{'role': 'master'}" 

# host group for etcd
[etcd]
$MASTER

# host group for nodes
[nodes]
$MASTER openshift_node_labels="{'region': 'master', 'zone': 'default'}"
$INFRA openshift_node_labels="{'region': 'infra', 'zone': 'default'}"

EOF

for (( c=0; c<$NODECOUNT; c++ ))
do
  echo "$NODE-$c openshift_node_labels=\"{'region': 'nodes', 'zone': 'default'}\"" >> /etc/ansible/hosts
done


# Initiating installation of OpenShift Enterprise using Ansible Playbook
echo $(date) " - Installing OpenShift Enterprise via Ansible Playbook"

runuser -l $SUDOUSER -c "ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/byo/config.yml"

echo $(date) " - Modifying sudoers"

sed -i -e "s/Defaults    requiretty/# Defaults    requiretty/" /etc/sudoers
sed -i -e '/Defaults    env_keep += "LC_TIME LC_ALL LANGUAGE LINGUAS _XKB_CHARSET XAUTHORITY"/aDefaults    env_keep += "PATH"' /etc/sudoers

# Deploying Registry
echo $(date) "- Registry deployed to infra node"

# Deploying Router
echo $(date) "- Router deployed to infra nodes"

echo $(date) "- Re-enabling requiretty"

sed -i -e "s/# Defaults    requiretty/Defaults    requiretty/" /etc/sudoers

# Adding user to OpenShift authentication file
echo $(date) "- Adding OpenShift user"

mkdir -p /etc/origin/master
htpasswd -cb /etc/origin/master/htpasswd $SUDOUSER $PASSWORD

echo $(date) " - Script complete"
