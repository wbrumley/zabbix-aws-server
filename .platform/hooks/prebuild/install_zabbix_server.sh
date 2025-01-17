#!/bin/bash

set -e

echo "Starting Zabbix Server Installation with RDS Integration..."

# Variables
DB_ROOT_PASSWORD="Q6L-MntJB68KFVRX"
RDS_ENDPOINT="zabbix.cjguswuy0jwt.us-east-1.rds.amazonaws.com"
ZBX_DB_NAME="zabbix"
ZBX_DB_USER="zabbix"
ZBX_DB_PASSWORD="zabbix"
NGINX_CONFIG_PATH="/etc/nginx/conf.d/zabbix.conf"
TIMEZONE="UTC"

# Install required packages
echo "Installing Zabbix server and related packages..."
sudo dnf install -y https://repo.zabbix.com/zabbix/6.0/amazonlinux/2023/aarch64/zabbix-release-6.0-4.amzn2023.noarch.rpm
sudo dnf clean all
sudo dnf install -y zabbix-server-mysql zabbix-web-mysql zabbix-nginx-conf mysql-client nginx php-fpm

# Configure Zabbix database and user on RDS
echo "Configuring Zabbix database on RDS..."
mysql -h "${RDS_ENDPOINT}" -u admin -p"${DB_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS ${ZBX_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${ZBX_DB_USER}'@'%' IDENTIFIED BY '${ZBX_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${ZBX_DB_NAME}.* TO '${ZBX_DB_USER}'@'%';
FLUSH PRIVILEGES;
EOF

# Import the initial Zabbix schema
echo "Importing Zabbix database schema into RDS..."
zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -h "${RDS_ENDPOINT}" -u"${ZBX_DB_USER}" -p"${ZBX_DB_PASSWORD}" "${ZBX_DB_NAME}"

# Configure Zabbix server
echo "Configuring Zabbix server..."
sudo sed -i "s/^# DBHost=.*/DBHost=${RDS_ENDPOINT}/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^# DBPassword=/DBPassword=${ZBX_DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^# DBUser=.*/DBUser=${ZBX_DB_USER}/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^# DBName=.*/DBName=${ZBX_DB_NAME}/" /etc/zabbix/zabbix_server.conf

# Configure Nginx for Zabbix
echo "Configuring Nginx..."
cat <<EOF | sudo tee ${NGINX_CONFIG_PATH}
server {
    listen       80;
    server_name  localhost;

    root /usr/share/zabbix;
    index index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        fastcgi_pass   unix:/run/php-fpm/www.sock;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include        fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx

# Start and enable services
echo "Starting Zabbix and PHP-FPM services..."
sudo systemctl enable zabbix-server
sudo systemctl start zabbix-server
sudo systemctl enable php-fpm
sudo systemctl restart php-fpm

echo "Zabbix Server installation and configuration complete!"
