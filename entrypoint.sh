#!/bin/bash
set -e

# Environment variables with defaults
MYSQL_HOST=${MYSQL_HOST:-pdnsdb}
MYSQL_DATABASE=${MYSQL_DATABASE:-powerdns}
MYSQL_USER=${MYSQL_USER:-pdns}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-pdnspassword}
PDNS_API_KEY=${PDNS_API_KEY:-changeme}
PDNS_WEBSERVER_PORT=${PDNS_WEBSERVER_PORT:-8081}
PDNS_WEBSERVER_ADDRESS=${PDNS_WEBSERVER_ADDRESS:-0.0.0.0}
PDNS_WEBSERVER_ALLOW_FROM=${PDNS_WEBSERVER_ALLOW_FROM:-0.0.0.0/0}

# Wait for MySQL to be available
echo "Waiting for MySQL at $MYSQL_HOST..."
until mysql -h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE -e 'SELECT 1;' >/dev/null 2>&1; do
  echo "MySQL not ready, waiting..."
  sleep 5
done
echo "MySQL is ready!"

# Test database connection and initialize schema if needed
echo "Testing database connection..."
mysql -h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE -e 'SELECT 1;' >/dev/null 2>&1

# Check if PowerDNS tables exist, create if not
TABLE_COUNT=$(mysql -h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE -e "
SELECT COUNT(*) as count FROM information_schema.tables 
WHERE table_schema = '$MYSQL_DATABASE' AND table_name IN ('domains', 'records', 'domainmetadata');
" | tail -n 1)

if [ "$TABLE_COUNT" -lt 3 ]; then
    echo "PowerDNS tables not found, creating schema..."
    mysql -h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE << 'EOF'
CREATE TABLE domains (
  id                    INT AUTO_INCREMENT,
  name                  VARCHAR(255) NOT NULL,
  master                VARCHAR(128) DEFAULT NULL,
  last_check            INT DEFAULT NULL,
  type                  VARCHAR(6) NOT NULL,
  notified_serial       INT UNSIGNED DEFAULT NULL,
  account               VARCHAR(40) CHARACTER SET 'utf8' DEFAULT NULL,
  PRIMARY KEY (id)
) Engine=InnoDB CHARACTER SET 'latin1';

CREATE UNIQUE INDEX name_index ON domains(name);

CREATE TABLE records (
  id                    BIGINT AUTO_INCREMENT,
  domain_id             INT DEFAULT NULL,
  name                  VARCHAR(255) DEFAULT NULL,
  type                  VARCHAR(10) DEFAULT NULL,
  content               VARCHAR(64000) DEFAULT NULL,
  ttl                   INT DEFAULT NULL,
  prio                  INT DEFAULT NULL,
  disabled              TINYINT(1) DEFAULT 0,
  ordername             VARCHAR(255) BINARY DEFAULT NULL,
  auth                  TINYINT(1) DEFAULT 1,
  PRIMARY KEY (id)
) Engine=InnoDB CHARACTER SET 'latin1';

CREATE INDEX nametype_index ON records(name,type);
CREATE INDEX domain_id ON records(domain_id);
CREATE INDEX ordername ON records (ordername);

CREATE TABLE supermasters (
  ip                    VARCHAR(64) NOT NULL,
  nameserver            VARCHAR(255) NOT NULL,
  account               VARCHAR(40) CHARACTER SET 'utf8' NOT NULL,
  PRIMARY KEY (ip, nameserver)
) Engine=InnoDB CHARACTER SET 'latin1';

CREATE TABLE comments (
  id                    INT AUTO_INCREMENT,
  domain_id             INT NOT NULL,
  name                  VARCHAR(255) NOT NULL,
  type                  VARCHAR(10) NOT NULL,
  modified_at           INT NOT NULL,
  account               VARCHAR(40) CHARACTER SET 'utf8' DEFAULT NULL,
  comment               TEXT CHARACTER SET 'utf8' NOT NULL,
  PRIMARY KEY (id)
) Engine=InnoDB CHARACTER SET 'latin1';

CREATE INDEX comments_name_type_idx ON comments (name, type);
CREATE INDEX comments_order_idx ON comments (domain_id, modified_at);

CREATE TABLE domainmetadata (
  id                    INT AUTO_INCREMENT,
  domain_id             INT NOT NULL,
  kind                  VARCHAR(32),
  content               TEXT,
  PRIMARY KEY (id)
) Engine=InnoDB CHARACTER SET 'latin1';

CREATE INDEX domainmetadata_idx ON domainmetadata (domain_id, kind);

CREATE TABLE cryptokeys (
  id                    INT AUTO_INCREMENT,
  domain_id             INT NOT NULL,
  flags                 INT NOT NULL,
  active                BOOL,
  published             BOOL DEFAULT 1,
  content               TEXT,
  PRIMARY KEY(id)
) Engine=InnoDB CHARACTER SET 'latin1';

CREATE INDEX domainidindex ON cryptokeys(domain_id);

CREATE TABLE tsigkeys (
  id                    INT AUTO_INCREMENT,
  name                  VARCHAR(255),
  algorithm             VARCHAR(50),
  secret                VARCHAR(255),
  PRIMARY KEY (id)
) Engine=InnoDB CHARACTER SET 'latin1';

CREATE UNIQUE INDEX namealgoindex ON tsigkeys(name, algorithm);
EOF
    echo "PowerDNS schema created successfully"
else
    echo "PowerDNS schema already exists"
fi

mysql -h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE -e 'SHOW TABLES;'

# Configure PowerDNS
cat <<EOF > /etc/powerdns/pdns.conf
daemon=no
launch=gmysql
gmysql-host=$MYSQL_HOST
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

echo "Starting PowerDNS..."
exec pdns_server --daemon=no
