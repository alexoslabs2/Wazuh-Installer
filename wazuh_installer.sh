#!/bin/bash
#Author:  Alexos (alexos at alexos dot org)
#Date: 09/02/2023
#Reference: https://documentation.wazuh.com/current/deployment-options/elastic-stack/all-in-one-deployment/index.html

log=~/wazuh.log

#Check sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

clear
apt-get update > $log 

#Install Dependencies
echo -ne Installing Dependencies...
sleep 1
echo Done
apt-get install -y apt-transport-https zip unzip lsb-release curl gnupg sudo vim >> $log

#Install ElasticSeach
echo -e Installing and Configuring Elasticsearch...
curl -s https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/elasticsearch.gpg --import && chmod 644 /usr/share/keyrings/elasticsearch.gpg 
clear
echo -e Installing and Configuring Elasticsearch...
echo "deb [signed-by=/usr/share/keyrings/elasticsearch.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-7.x.list >> $log
apt-get update >> $log 
apt-get install -y elasticsearch=7.17.6 >> $log
curl -so /etc/elasticsearch/elasticsearch.yml https://packages.wazuh.com/4.3/tpl/elastic-basic/elasticsearch_all_in_one.yml
curl -so /usr/share/elasticsearch/instances.yml https://packages.wazuh.com/4.3/tpl/elastic-basic/instances_aio.yml
/usr/share/elasticsearch/bin/elasticsearch-certutil cert ca --pem --in instances.yml --keep-ca-key --out ~/certs.zip >> $log
unzip ~/certs.zip -d ~/certs >> $log
mkdir /etc/elasticsearch/certs/ca -p
cp -R ~/certs/ca/ ~/certs/elasticsearch/* /etc/elasticsearch/certs/
chown -R elasticsearch: /etc/elasticsearch/certs
chmod -R 500 /etc/elasticsearch/certs
chmod 400 /etc/elasticsearch/certs/ca/ca.* /etc/elasticsearch/certs/elasticsearch.*
rm -rf ~/certs/ ~/certs.zip
systemctl daemon-reload >> $log
systemctl enable elasticsearch >> $log
clear
echo -ne Starting Elasticsearch...
systemctl start elasticsearch
sleep 1
echo Done 

echo -e Elasticsearch is $(systemctl status elasticsearch | grep "Active:" | awk '{print $3}')

echo y | sudo /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto | grep "PASSWORD elastic" >> /tmp/elastic.txt 
export ELASTICPASS=$(awk '{print $4}' /tmp/elastic.txt)

echo -e Testing Elasticseach...
curl -XGET https://localhost:9200 -u elastic:$ELASTICPASS -k
sleep 2
clear

#Install Wazuh
echo -e Installing Wazuh Server and Manager...
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg
clear
echo -e Installing Wazuh Server and Manager...
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee -a /etc/apt/sources.list.d/wazuh.list >> $log
apt-get update >> $log
apt-get install -y wazuh-manager >> $log
systemctl daemon-reload >> $log
systemctl enable wazuh-manager >> $log
clear
echo -ne Starting Wazuh Manager...
systemctl start wazuh-manager
sleep 1
echo Done

echo -e Wazuh Manager is $(systemctl status wazuh-manager | grep "Active:" | awk '{print $3}')
sleep 1
clear

#Install Filebeat
echo -e Installing Filebeat...
apt-get install -y filebeat=7.17.6 >> $log

curl -so /etc/filebeat/filebeat.yml https://packages.wazuh.com/4.3/tpl/elastic-basic/filebeat_all_in_one.yml

curl -so /etc/filebeat/wazuh-template.json https://raw.githubusercontent.com/wazuh/wazuh/4.3/extensions/elasticsearch/7.x/wazuh-template.json

chmod go+r /etc/filebeat/wazuh-template.json
curl -s https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.2.tar.gz | tar -xvz -C /usr/share/filebeat/module >> $log

export ELASTICPASS=$(awk '{print $4}' /tmp/elastic.txt)
sed -i "s/<elasticsearch_password>/$ELASTICPASS/g" /etc/filebeat/filebeat.yml

cp -r /etc/elasticsearch/certs/ca/ /etc/filebeat/certs/
cp /etc/elasticsearch/certs/elasticsearch.crt /etc/filebeat/certs/filebeat.crt
cp /etc/elasticsearch/certs/elasticsearch.key /etc/filebeat/certs/filebeat.key

systemctl daemon-reload >> $log
systemctl enable filebeat >> $log
clear
echo -ne Starting Filebeat...
systemctl start filebeat
sleep 1
echo Done

echo -e Filebeat is $(systemctl status filebeat| grep "Active:" | awk '{print $3}')

echo -e Testing Filebeat...
filebeat test output
sleep 2
clear

#Install Kibana
echo Installing Kibana...
apt-get install kibana=7.17.6 >> $log

mkdir /etc/kibana/certs/ca -p
cp -R /etc/elasticsearch/certs/ca/ /etc/kibana/certs/
cp /etc/elasticsearch/certs/elasticsearch.key /etc/kibana/certs/kibana.key
cp /etc/elasticsearch/certs/elasticsearch.crt /etc/kibana/certs/kibana.crt
chown -R kibana:kibana /etc/kibana/
chmod -R 500 /etc/kibana/certs
chmod 440 /etc/kibana/certs/ca/ca.* /etc/kibana/certs/kibana.*

curl -so /etc/kibana/kibana.yml https://packages.wazuh.com/4.3/tpl/elastic-basic/kibana_all_in_one.yml

export ELASTICPASS=$(awk '{print $4}' /tmp/elastic.txt)
sed -i "s/<elasticsearch_password>/$ELASTICPASS/g" /etc/kibana/kibana.yml

mkdir /usr/share/kibana/data
chown -R kibana:kibana /usr/share/kibana

cd /usr/share/kibana
sudo -u kibana /usr/share/kibana/bin/kibana-plugin install https://packages.wazuh.com/4.x/ui/kibana/wazuh_kibana-4.3.10_7.17.6-1.zip >> $log

/usr/sbin/setcap 'cap_net_bind_service=+ep' /usr/share/kibana/node/bin/node

systemctl daemon-reload >> $log
systemctl enable kibana >> $log
clear
echo -ne Starting Kibana...
systemctl start kibana
sleep 1
echo Done

echo -e Kibana is $(systemctl status kibana | grep "Active:" | awk '{print $3}')
sleep 1
clear
echo -e Wazuh Installation Finished!

# Infos
echo -e "== Access Information =="
echo URL: https://$(hostname -I)
echo user: elastic
echo password: $(awk '{print $4}' /tmp/elastic.txt)

echo -e "Warning: Change the password"

#Cleaning 
echo -ne Cleaning...
sed -i "s/^deb/#deb/" /etc/apt/sources.list.d/wazuh.list
sed -i "s/^deb/#deb/" /etc/apt/sources.list.d/elastic-7.x.list
apt-get update >> $log
rm /tmp/elastic.txt
sleep 1
echo Done
