#!/bin/bash
set -e


# Start MariaDB in the background
service mariadb start

# Wait for MariaDB to be ready
until mysqladmin ping --silent; do
  echo 'Waiting for MariaDB...'
  sleep 2
done

# Create PowerDNS database and user if not exists
mysql -uroot -proot_pass <<EOSQL
CREATE DATABASE IF NOT EXISTS pdns;
CREATE USER IF NOT EXISTS 'pdns'@'localhost' IDENTIFIED BY 'pdns_pass';
GRANT ALL PRIVILEGES ON pdns.* TO 'pdns'@'localhost';
FLUSH PRIVILEGES;
EOSQL

# Import PowerDNS schema if not already imported
if ! mysql -updns -ppdns_pass pdns -e 'SHOW TABLES;' | grep domains; then
  if [ -f /usr/share/pdns-backend-mysql/schema/schema.mysql.sql ]; then
    mysql -updns -ppdns_pass pdns < /usr/share/pdns-backend-mysql/schema/schema.mysql.sql
  fi
fi

# Configure PowerDNS
cat <<EOF > /etc/powerdns/pdns.conf
daemon=no
launch=gmysql
gmysql-host=localhost
gmysql-user=pdns
gmysql-password=pdns_pass
gmysql-dbname=pdns
api=yes
api-key=changeme
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081
EOF

# Start PowerDNS
exec pdns_server --daemon=no
