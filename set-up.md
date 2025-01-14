# **Creating a Zabbix Server Using AWS EC2 and RDS**

## Prerequisites

#### 1. Create an EC2 instance with the following properties:
* 20 GiB gp3 storage
* Amazon Linux 2023
* 64-bit (Arm)
* t4g-micro

#### 2. Attach a security group to the EC2 instance allowing inbound connections from port 80, 443, 10051 (Zabbix server), 10050 (for Zabbix agent installed on server)

#### 3. Create an RDS instance with the following properties:
* MySQL 8.0.39
* db.t3.small
* 100 GiB gp3 storage
* A custom parameter group must be created and attached during configuration with ‘log_bin_trust_function_creators’ set to ‘1’ to import initial schema:

![image](https://github.com/user-attachments/assets/a6b35951-bcb0-4590-b3b6-c106b17d93bc)


#### 4. The security group for the MySQL database will need to connect to the server and allow connections from the EC2 instance’s private IP on port 3306. This can be configured through the AWS console during the RDS instance’s creation:

![image](https://github.com/user-attachments/assets/4f357c2d-290b-4f72-ade0-11f412c601b7)


## Step 1:  Install Zabbix and Dependencies on EC2 instance

#### 1. Connect to the EC2 instance and install the Zabbix repository and its dependencies using DNF package manager:
```
dnf install https://repo.zabbix.com/zabbix/7.2/release/amazonlinux/2023/noarch/zabbix-release-7.2-1.amzn2023.noarch.rpm
dnf clean all
dnf install zabbix-server-mysql zabbix-web-mysql zabbix-nginx-conf zabbix-sql-scripts zabbix-agent
```

#### 2. Configure Zabbix files:
`nano /etc/zabbix/zabbix_server.conf`

Enable and edit these fields to the following:

| Property      | Value                   |
| ------------- |:-----------------------:|
| DBHost=       | <&#8203;rds-endpoint>        |
| DBName=       | <&#8203;zabbix-db-name>      |
| DBUser=       | zabbix                  |
| DBPassword=   | <&#8203;zabbix-user-password> |

#### 3. Install MySQL Community Edition client:
```
dnf install -y https://dev.mysql.com/get/mysql84-community-release-el9-1.noarch.rpm
dnf install -y mysql
```
## Step 2: Create database, configure users, and import schema:

#### 1. Use the RDS instance's master credentials to connect:
`mysql -u <RDS master user> -p -h <RDS-endpoint>`

#### 2. Create the database and a "zabbix" user with appropriate permissions:
```
CREATE DATABASE <zabbix-db-name> CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'%' IDENTIFIED BY '<zabbix-user-password>';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'%';
FLUSH PRIVILEGES;
EXIT;
```

#### 3. Import database schema from Zabbix files:
`zcat /usr/share/zabbix/sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p -h <RDS-endpoint> <zabbix-db-name>`

## Step 3: Configure NGINX and enable Zabbix server:

#### 1. Edit NGINX configuration files to listen on port 80 and point to the server's public IP or domain:
`nano /etc/nginx/conf.d/zabbix.conf`

```
server {
    listen 80;
    server_name <server_public_ip_or_domain>;

    root /usr/share/zabbix;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php-fpm/www.sock; # Use PHP-FPM socket
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }

    location ~* \.(jpg|jpeg|gif|css|png|js|ico|xml|woff|ttf|svg|html|map|htm)$ {
        access_log off;
        expires max;
    }
}
```

#### 2. Test new NGINX configuration:
`nginx -t`

#### 3. Start and enable NGINX/Zabbix:
```
systemctl start nginx php-fpm
systemctl enable nginx php-fpm

systemctl start zabbix-server
systemctl enable zabbix-server
```

## Step 4: Complete installation using Zabbix frontend:

#### 1. Go to http://<&#8203;EC2-instance-public-IP>

#### 2. Complete the installation wizard:

![image](https://github.com/user-attachments/assets/165194aa-da41-4340-98b1-685039a552bf)

#### 3. Enter the MySQL database details:

![image](https://github.com/user-attachments/assets/d3f53248-f3d0-4a55-b48c-ccdab37e0c09)


#### 4. It is now possible to login to the portal at http://<&#8203;EC2-instance-public-IP>/zabbix with the default credentials
| Default user      | Default password                   |
| ------------- |:-----------------------:|
| Admin      | zabbix        |

#### 5. Change default credentials in the portal and secure communication with SSL certificate

## Step 5: Configure Zabbix agent installed locally on Zabbix server:

#### 1. Edit the Zabbix agent configuration file:
`nano /etc/zabbix/zabbix_agentd.conf`

| Property        | Value       |
| -------------   |:-----------:|
| Server=         |127.0.0.1    |
| ServerActive=   | 127.0.0.1   |
| Hostname=       | hostname    |

#### 2. Restart the Zabbix agent:
`systemctl restart zabbix-agent`

#### 3. The Zabbix server should now be available to monitor in the dashboards:

![image](https://github.com/user-attachments/assets/9fdd4933-2a4b-41d3-8720-ab572b59c244)
