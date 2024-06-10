#!/bin/bash
sudo yum install -y ansible-core git python3-pip
sudo pip3 install --upgrade pip
ansible-galaxy collection install azure.azcollection
ansible-galaxy collection install redhat.openshift
echo "[default]"                        >> ~/.azure/credentials
echo subscription_id=${subscription}    >> ~/.azure/credentials
echo client_id=${client_id}             >> ~/.azure/credentials
echo tenant=${tenant}                   >> ~/.azure/credentials
echo secret=${secret}                   >> ~/.azure/credentials

