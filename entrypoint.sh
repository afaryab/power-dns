#!/bin/bash
set -e

# Environment variables with defaults
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-root_pass}
MYSQL_DATABASE=${MYSQL_DATABASE:-pdns}
MYSQL_USER=${MYSQL_USER:-pdns}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-pdns_pass}
PDNS_API_KEY=${PDNS_API_KEY:-changeme}
PDNS_WEBSERVER_PORT=${PDNS_WEBSERVER_PORT:-8081}
PDNS_WEBSERVER_ADDRESS=${PDNS_WEBSERVER_ADDRESS:-0.0.0.0}
PDNS_WEBSERVER_ALLOW_FROM=${PDNS_WEBSERVER_ALLOW_FROM:-0.0.0.0/0}

# Initialize MariaDB data directory if it doesn't exist or is empty
if [ ! -d "/var/lib/mysql/mysql" ]; then
  echo "Initializing MariaDB data directory..."
  mysql_install_db --user=mysql --datadir=/var/lib/mysql
fi

# Start MariaDB in the background
service mariadb start

# Wait for MariaDB to be ready
until mysqladmin ping --silent; do
  echo 'Waiting for MariaDB...'
  sleep 2
done

# Set root password if not already set
mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';" 2>/dev/null || true

# Create PowerDNS database and user if not exists
mysql -uroot -p$MYSQL_ROOT_PASSWORD <<EOSQL
CREATE DATABASE IF NOT EXISTS $MYSQL_DATABASE;
CREATE USER IF NOT EXISTS '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';
GRANT ALL PRIVILEGES ON $MYSQL_DATABASE.* TO '$MYSQL_USER'@'localhost';
FLUSH PRIVILEGES;
EOSQL

# Import PowerDNS schema if not already imported
if ! mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE -e 'SHOW TABLES;' | grep domains; then
  if [ -f /usr/share/pdns-backend-mysql/schema/schema.mysql.sql ]; then
    mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE < /usr/share/pdns-backend-mysql/schema/schema.mysql.sql
  fi
fi

# Configure PowerDNS
cat <<EOF > /etc/powerdns/pdns.conf
daemon=no
launch=gmysql
gmysql-host=localhost
gmysql-user=$MYSQL_USER
gmysql-password=$MYSQL_PASSWORD
gmysql-dbname=$MYSQL_DATABASE
api=yes
api-key=$PDNS_API_KEY
webserver=yes
webserver-address=$PDNS_WEBSERVER_ADDRESS
webserver-port=$PDNS_WEBSERVER_PORT
webserver-allow-from=$PDNS_WEBSERVER_ALLOW_FROM
EOF

# Start PowerDNS
exec pdns_server --daemon=no
