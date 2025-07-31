#!/bin/bash
set -e

# Environment variables with defaults
MYSQL_HOST=${MYSQL_HOST:-pdnsdb}
MYSQL_PORT=${MYSQL_PORT:-3306}
MYSQL_DATABASE=${MYSQL_DATABASE:-powerdns}
MYSQL_USER=${MYSQL_USER:-pdns}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-pdnspassword}
PDNS_API_URL=${PDNS_API_URL:-http://pdnsapp:8081}
PDNS_API_KEY=${PDNS_API_KEY:-changeme}

export SQLALCHEMY_DATABASE_URI="mysql://$MYSQL_USER:$MYSQL_PASSWORD@$MYSQL_HOST:$MYSQL_PORT/$MYSQL_DATABASE"

echo "Waiting for MySQL at $MYSQL_HOST:$MYSQL_PORT..."
while ! nc -z $MYSQL_HOST $MYSQL_PORT >/dev/null 2>&1; do
    echo "MySQL not ready, waiting..."
    sleep 5
done
echo "MySQL is ready!"

echo "Waiting for PowerDNS API at $PDNS_API_URL..."
while ! curl -s "$PDNS_API_URL/api/v1/servers" -H "X-API-Key: $PDNS_API_KEY" >/dev/null 2>&1; do
    echo "PowerDNS API not ready, waiting..."
    sleep 5
done
echo "PowerDNS API is ready!"

# Initialize database
echo "Initializing PowerDNS Admin database..."
cd /opt/powerdns-admin
python3 init_db.py

# Create session directory
mkdir -p /tmp/powerdns-admin-sessions
chown -R pdnsadmin:pdnsadmin /tmp/powerdns-admin-sessions

echo "Starting PowerDNS-Admin with Gunicorn..."

# Set PYTHONPATH and create app factory
export PYTHONPATH="/opt/powerdns-admin:$PYTHONPATH"

# Start Gunicorn with proper user switching
exec gosu pdnsadmin gunicorn \
    --bind 0.0.0.0:80 \
    --workers 4 \
    --timeout 120 \
    --access-logfile - \
    --error-logfile - \
    --log-level info \
    --worker-class sync \
    --max-requests 1000 \
    --max-requests-jitter 100 \
    --preload \
    --chdir /opt/powerdns-admin \
    "powerdnsadmin:create_app(config='/etc/powerdns-admin/production_config.py')"
