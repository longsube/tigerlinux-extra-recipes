#!/bin/bash
#
# Reynaldo R. Martinez P.
# tigerlinux@gmail.com
# http://tigerlinux.github.io
# https://github.com/tigerlinux
# ELK Stack Server Setup for Centos 7 64 bits
# (ELK = ElasticSearch, Logstack, Kibana)
# Release 1.3
#

PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

export lgfile="/var/log/elk-stack-automated-install.log"
echo "Start Date/Time: `date`" &>>$lgfile
export credentialsfile="/root/elk-stack-credentials.txt"
export OSFlavor='unknown'
# Set your java preference... either OpenJDK or Oracle JDK
# The next variable should be set to:
# javaversion="openjdk"   # OpenJDK
# javaversion="oraclejdk" # Oracke JDK
javaversion="oraclejdk"

if [ -f /etc/centos-release ]
then
	OSFlavor='centos-based'
	yum clean all
	yum -y install coreutils grep curl wget redhat-lsb-core net-tools git \
	findutils iproute grep openssh sed gawk openssl which xz bzip2 util-linux \
	procps-ng which lvm2 sudo hostname &>>$lgfile
	setenforce 0
	sed -r -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
	sed -r -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
else
	echo "Not a centos server. Aborting!" &>>$lgfile
	exit 0
fi

if [ `uname -p 2>/dev/null|grep x86_64|head -n1|wc -l` != "1" ]
then
	echo "Not a 64 bits machine. Aborting !" &>>$lgfile
	echo "End Date/Time: `date`" &>>$lgfile
	exit 0
fi

export kibanaadminpass=`openssl rand -hex 10`

cpus=`lscpu -a --extended|grep -ic yes`
instram=`free -m -t|grep -i mem:|awk '{print $2}'`
avusr=`df -k --output=avail /usr|tail -n 1`
avvar=`df -k --output=avail /var|tail -n 1`

if [ $cpus -lt "2" ] || [ $instram -lt "3500" ] || [ $avusr -lt "5000000" ] || [ $avvar -lt "5000000" ]
then
	echo "Not enough hardware for ELK Stack. Aborting!" &>>$lgfile
	echo "End Date/Time: `date`" &>>$lgfile
	exit 0
fi

if [ `grep -c swapfile /etc/fstab` == "0" ]
then
	myswap=`free -m -t|grep -i swap:|awk '{print $2}'`
	if [ $myswap -lt 2000 ]
	then
		fallocate -l 2G /swapfile
		chmod 600 /swapfile
		mkswap /swapfile
		swapon /swapfile
		echo '/swapfile none swap sw 0 0' >> /etc/fstab
	fi
fi

amicen=`lsb_release -i|grep -ic centos`
crel7=`lsb_release -r|awk '{print $2}'|grep ^7.|wc -l`
if [ $amicen != "1" ] || [ $crel7 != "1" ]
then
	echo "This is NOT a Centos 7 machine. Aborting !"
	echo "End Date/Time: `date`" &>>$lgfile
	exit 0
fi

# Kill packet.net repositories if detected here.
yum -y install yum-utils &>>$lgfile
repotokill=`yum repolist|grep -i ^packet|cut -d/ -f1`
for myrepo in $repotokill
do
	echo "Disabling repo: $myrepo" &>>$lgfile
	yum-config-manager --disable $myrepo &>>$lgfile
done

yum -y install epel-release &>>$lgfile
yum -y install device-mapper-persistent-data unzip &>>$lgfile

yum -y update --exclude=kernel* &>>$lgfile

yum -y install firewalld &>>$lgfile
systemctl enable firewalld
systemctl restart firewalld
firewall-cmd --zone=public --add-service=http --permanent
firewall-cmd --zone=public --add-service=https --permanent
firewall-cmd --zone=public --add-service=ssh --permanent
firewall-cmd --zone=public --add-port=5044/tcp --permanent
firewall-cmd --reload

case $javaversion in
"oraclejdk")
	wget \
	--no-cookies \
	--no-check-certificate \
	--header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" \
	"http://download.oracle.com/otn-pub/java/jdk/8u144-b01/090f390dda5b47b9b721c7dfaa008135/jdk-8u144-linux-x64.rpm" \
	-O /root/jdk-8u144-linux-x64.rpm &>>$lgfile
	yum -y localinstall /root/jdk-8u144-linux-x64.rpm &>>$lgfile
	sync
	rm -f /root/jdk-8u144-linux-x64.rpm
	if [ `which java 2>/dev/null|wc -l` == "0" ]
	then
		yum -y install java-1.8.0-openjdk &>>$lgfile
	fi
	;;
"openjdk")
	yum -y install java-1.8.0-openjdk &>>$lgfile
	;;
*)
	yum -y install java-1.8.0-openjdk &>>$lgfile
	;;
esac

rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch &>>$lgfile

cat<<EOF>/etc/yum.repos.d/elasticsearch.repo
[elasticsearch-5.x]
name=Elasticsearch repository for 5.x packages
baseurl=https://artifacts.elastic.co/packages/5.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
EOF

echo "net.ipv4.tcp_timestamps = 0" > /etc/sysctl.d/10-disable-timestamps.conf
sysctl -p /etc/sysctl.d/10-disable-timestamps.conf

yum -y update --exclude=kernel* &>>$lgfile

yum -y install elasticsearch &>>$lgfile

sed -r -i 's/^#network.host.*/network.host:\ 127.0.0.1/g' /etc/elasticsearch/elasticsearch.yml
sed -r -i 's/^#http.port.*/http.port:\ 9200/g' /etc/elasticsearch/elasticsearch.yml
systemctl start elasticsearch
systemctl enable elasticsearch

# ElasticSearch stabilization time.
sleep 60

yum -y install kibana &>>$lgfile
sed -r -i 's/^#server.host.*/server.host:\ \"localhost\"/g' /etc/kibana/kibana.yml

systemctl start kibana
systemctl enable kibana

yum -y install nginx httpd-tools &>>$lgfile

htpasswd -b -c /etc/nginx/htpasswd.users admin $kibanaadminpass

echo "Your KIBANA Credentials are:" >> $credentialsfile
echo "User: admin" >> $credentialsfile
echo "Password: $kibanaadminpass" >> $credentialsfile
echo "URL: http://`ip route get 1 | awk '{print $NF;exit}'`" >> $credentialsfile

cat /etc/nginx/nginx.conf >> /etc/nginx/nginx.conf.original

openssl dhparam -out /etc/nginx/dhparams.pem 2048

cat <<EOF >/etc/nginx/nginx.conf
include /usr/share/nginx/modules/*.conf;
events {
    worker_connections 1024;
}
http {
  client_max_body_size 1000m;
  log_format  main  '\$remote_addr - \$remote_user [$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

   access_log  /var/log/nginx/access.log  main;
   sendfile            on;
   tcp_nopush          on;
   tcp_nodelay         on;
   keepalive_timeout   65;
   types_hash_max_size 2048;
   include             /etc/nginx/mime.types;
   default_type        application/octet-stream;
   include /etc/nginx/conf.d/*.conf;
   server {
      listen       80 default_server;
      listen       [::]:80 default_server;

      server_name _;
      auth_basic "Restricted Access";
      auth_basic_user_file /etc/nginx/htpasswd.users;

      location / {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_pass http://127.0.0.1:5601;
     }
   }
   server {
      listen       443 ssl http2 default_server;
      listen       [::]:443 ssl http2 default_server;
      ssl_certificate "/etc/pki/nginx/server.crt";
      ssl_certificate_key "/etc/pki/nginx/private/server.key";
      include /etc/nginx/default.d/sslconfig.conf;

      server_name _;
      auth_basic "Restricted Access";
      auth_basic_user_file /etc/nginx/htpasswd.users;

      location / {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_pass http://127.0.0.1:5601;
     }
   }
}
EOF

cat <<EOF>/etc/nginx/default.d/sslconfig.conf
ssl_session_cache shared:SSL:1m;
ssl_session_timeout  10m;
ssl_prefer_server_ciphers on;
ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:!DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA';
ssl_dhparam /etc/nginx/dhparams.pem;
EOF

mkdir -p /etc/pki/nginx
mkdir -p /etc/pki/nginx/private

openssl req -x509 -batch -nodes -days 365 -newkey rsa:2048 -keyout /etc/pki/nginx/private/server.key -out /etc/pki/nginx/server.crt &>>$lgfile

chmod 0600 /etc/pki/nginx/private/server.key
chown nginx.nginx /etc/pki/nginx/private/server.key

systemctl restart nginx
systemctl enable nginx

yum -y install logstash &>>$lgfile

mkdir /etc/pki/CA-ELK

wget https://storage.googleapis.com/kubernetes-release/easy-rsa/easy-rsa.tar.gz -O /root/easy-rsa.tar.gz &>>$lgfile
tar -xzvf /root/easy-rsa.tar.gz -C /root/ &>>$lgfile
cd /root/easy-rsa-master/easyrsa3/
./easyrsa init-pki &>>$lgfile
./easyrsa --batch "--req-cn=`ip route get 1 | awk '{print $NF;exit}'`@`date +%s`" build-ca nopass &>>$lgfile
./easyrsa --subject-alt-name="IP:`ip route get 1 | awk '{print $NF;exit}'`,IP:127.0.0.1,DNS:`hostname`" build-server-full server nopass &>>$lgfile
for i in {pki/ca.crt,pki/issued/server.crt,pki/private/server.key}; do cp $i /etc/pki/CA-ELK; done
# Server
./easyrsa --batch gen-req client1 nopass &>>$lgfile
./easyrsa --batch sign-req client client1 &>>$lgfile
cp ./pki/issued/client1.crt ./pki/private/client1.key /etc/pki/CA-ELK/
openssl x509 -outform PEM -in /etc/pki/CA-ELK/server.crt -out /etc/pki/CA-ELK/server.pem &>>$lgfile
chmod 0600 /etc/pki/CA-ELK/server.key
chmod 0600 /etc/pki/CA-ELK/client1.key
openssl x509 -outform PEM -in /etc/pki/CA-ELK/client1.crt -out /etc/pki/CA-ELK/client1.pem &>>$lgfile
chown logstash. /etc/pki/CA-ELK/server.key
chmod 644 /etc/pki/CA-ELK/ca.crt
chmod 644 /etc/pki/CA-ELK/server.pem
rm -f /root/easy-rsa.tar.gz
cp /etc/pki/CA-ELK/ca.crt /etc/pki/ca-trust/source/anchors/
cd /
update-ca-trust &>>$lgfile


cat<<EOF >/etc/logstash/conf.d/02-beats-input.conf
input {
 beats {
  port => 5044
  ssl => true
  ssl_certificate_authorities => "/etc/pki/CA-ELK/ca.crt"
  ssl_certificate => "/etc/pki/CA-ELK/server.pem"
  ssl_key => "/etc/pki/CA-ELK/server.key"
  ssl_verify_mode => "none"
 }
}
EOF

cat<<EOF >/etc/logstash/conf.d/10-syslog-filter.conf
filter {
  if [type] == "syslog" {
    grok {
      match => { "message" => "%{SYSLOGTIMESTAMP:syslog_timestamp} %{SYSLOGHOST:syslog_hostname} %{DATA:syslog_program}(?:\[%{POSINT:syslog_pid}\])?: %{GREEDYDATA:syslog_message}" }
      add_field => [ "received_at", "%{@timestamp}" ]
      add_field => [ "received_from", "%{host}" ]
    }
    syslog_pri { }
    date {
     match => [ "syslog_timestamp", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss" ]
    }
  }
}
EOF

cat<<EOF >/etc/logstash/conf.d/30-elasticsearch-output.conf
output {
  elasticsearch {
    hosts => ["127.0.0.1:9200"]
    sniffing => true
    manage_template => false
    index => "%{[@metadata][beat]}-%{+YYYY.MM.dd}"
    document_type => "%{[@metadata][type]}"
  }
}
EOF

# Config test
echo "Validating logstash config" &>>$lgfile
/usr/share/logstash/bin/logstash --config.test_and_exit -f /etc/logstash/conf.d/ &>>$lgfile

systemctl restart logstash
systemctl enable logstash
sleep 60
sync

yum -y install filebeat &>>$lgfile

cat<<EOF >/etc/filebeat/filebeat.yml
filebeat.prospectors:
- input_type: log
  paths:
    - /var/log/secure
    - /var/log/messages
    - /var/log/*.log
output.logstash:
  hosts: ["127.0.0.1:5044"]
  ssl.certificate_authorities: ["/etc/pki/CA-ELK/ca.crt"]
  ssl.certificate: "/etc/pki/CA-ELK/client1.pem"
  ssl.key: "/etc/pki/CA-ELK/client1.key"
EOF

systemctl start filebeat
systemctl enable filebeat

systemctl status elasticsearch &>>$lgfile
systemctl status kibana &>>$lgfile
systemctl status nginx &>>$lgfile
systemctl status logstash &>>$lgfile
systemctl status filebeat &>>$lgfile


if [ `ss -ltn|grep -c :80` -gt "0" ] && [ `ss -ltn|grep -c :9200` -gt "0" ] && [ `ss -ltn|grep -c :5044` -gt "0" ]
then
	echo "Your ELK Stack server is ready. See your credentials at $credentialsfile" &>>$lgfile
	cat $credentialsfile &>>$lgfile
else
	echo "ELK Stack Server install failed" &>>$lgfile
fi

echo "End Date/Time: `date`" &>>$lgfile

#END