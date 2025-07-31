#!/bin/bash
set -e

# Environment variables with defaults
PDNS_API_URL=${PDNS_API_URL:-http://pdnsapp:8081}
PDNS_API_KEY=${PDNS_API_KEY:-changeme}
SECRET_KEY=${SECRET_KEY:-changeme}
MYSQL_HOST=${MYSQL_HOST:-pdnsdb}
MYSQL_DATABASE=${MYSQL_DATABASE:-powerdns}
MYSQL_USER=${MYSQL_USER:-pdns}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-pdnspassword}
SQLALCHEMY_DATABASE_URI=${SQLALCHEMY_DATABASE_URI:-mysql+pymysql://$MYSQL_USER:$MYSQL_PASSWORD@$MYSQL_HOST/$MYSQL_DATABASE}
BIND_ADDRESS=${BIND_ADDRESS:-0.0.0.0}
PORT=${PORT:-80}

# Admin user configuration
ADMIN_USERNAME=${ADMIN_USERNAME:-admin}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin123}
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@local.domain}
ADMIN_FIRSTNAME=${ADMIN_FIRSTNAME:-Admin}
ADMIN_LASTNAME=${ADMIN_LASTNAME:-User}

# OTP/2FA configuration
OTP_ENABLED_VALUE=${OTP_ENABLED:-false}
if [[ "${OTP_ENABLED_VALUE,,}" == "true" ]]; then
    OTP_CONFIG="True"
else
    OTP_CONFIG="False"
fi

# Wait for MySQL to be available
echo "Waiting for MySQL at $MYSQL_HOST..."
until python3 -c "import pymysql; pymysql.connect(host='$MYSQL_HOST', user='$MYSQL_USER', password='$MYSQL_PASSWORD', db='$MYSQL_DATABASE')" 2>/dev/null; do
  echo "MySQL not ready, waiting..."
  sleep 5
done
echo "MySQL is ready!"

# Wait for PowerDNS API to be available
echo "Waiting for PowerDNS API at $PDNS_API_URL..."
while ! curl -s "$PDNS_API_URL/api/v1/servers" -H "X-API-Key: $PDNS_API_KEY" >/dev/null 2>&1; do
    echo "PowerDNS API not ready, waiting..."
    sleep 5
done
echo "PowerDNS API is ready!"

# Create configuration
cat > /opt/powerdns-admin/powerdnsadmin/default_config.py << EOF
import os

# Basic config
SECRET_KEY = '$SECRET_KEY'
BIND_ADDRESS = '$BIND_ADDRESS'
PORT = $PORT

# Database config
SQLALCHEMY_DATABASE_URI = '$SQLALCHEMY_DATABASE_URI'
SQLALCHEMY_TRACK_MODIFICATIONS = False

# PowerDNS API config
PDNS_STATS_URL = '$PDNS_API_URL'
PDNS_API_KEY = '$PDNS_API_KEY'
PDNS_VERSION = '4.5.3'

# Session config
SESSION_TYPE = 'filesystem'
SESSION_PERMANENT = False
SESSION_USE_SIGNER = True
SESSION_KEY_PREFIX = 'powerdns-admin:'
SESSION_FILE_DIR = '/tmp/powerdns-admin-sessions'
SESSION_FILE_THRESHOLD = 500
SESSION_FILE_MODE = 384

# Disable captcha completely to avoid session issues
CAPTCHA_ENABLE = False
SIGNUP_ENABLED = False

# Disable OTP/2FA by default (configurable via environment)
OTP_ENABLED = $OTP_CONFIG
OTP_FIELD_ENABLED = $OTP_CONFIG

# SAML configuration (disabled)
SAML_ENABLED = False
SAML_DEBUG = False
SAML_PATH = None
SAML_METADATA_URL = None
SAML_METADATA_CACHE_LIFETIME = 1
SAML_SP_ENTITY_ID = None
SAML_SP_CONTACT_NAME = None
SAML_SP_CONTACT_MAIL = None
SAML_SIGN_REQUEST = False
SAML_WANT_MESSAGE_SIGNED = False
SAML_LOGOUT = False
SAML_LOGOUT_URL = None

# OIDC configuration (disabled)
OIDC_OAUTH_ENABLED = False
OIDC_OAUTH_KEY = None
OIDC_OAUTH_SECRET = None
OIDC_OAUTH_SCOPE = None
OIDC_OAUTH_API_URL = None
OIDC_OAUTH_TOKEN_URL = None
OIDC_OAUTH_AUTHORIZE_URL = None

# GitHub OAuth (disabled)
GITHUB_OAUTH_ENABLED = False
GITHUB_OAUTH_KEY = None
GITHUB_OAUTH_SECRET = None
GITHUB_OAUTH_SCOPE = None
GITHUB_OAUTH_API_URL = None
GITHUB_OAUTH_TOKEN_URL = None
GITHUB_OAUTH_AUTHORIZE_URL = None

# Google OAuth (disabled)
GOOGLE_OAUTH_ENABLED = False
GOOGLE_OAUTH_CLIENT_ID = None
GOOGLE_OAUTH_CLIENT_SECRET = None
GOOGLE_OAUTH_SCOPE = None
GOOGLE_OAUTH_API_URL = None
GOOGLE_OAUTH_TOKEN_URL = None
GOOGLE_OAUTH_AUTHORIZE_URL = None

# Azure OAuth (disabled)
AZURE_OAUTH_ENABLED = False
AZURE_OAUTH_KEY = None
AZURE_OAUTH_SECRET = None
AZURE_OAUTH_SCOPE = None
AZURE_OAUTH_API_URL = None
AZURE_OAUTH_TOKEN_URL = None
AZURE_OAUTH_AUTHORIZE_URL = None

# Other settings
WTF_CSRF_TIME_LIMIT = None
RECORDS_ALLOW_EDIT = ['A', 'AAAA', 'CNAME', 'MX', 'PTR', 'SRV', 'TXT', 'NS', 'SOA']
FORWARD_RECORDS_ALLOW_EDIT = ['A', 'AAAA', 'CNAME', 'MX', 'PTR', 'SRV', 'TXT']
REVERSE_RECORDS_ALLOW_EDIT = ['PTR']
PRETTY_IPV6_PTR = False
DNSSEC_ADMINS_ONLY = True
BG_DOMAIN_UPDATES = False
ENABLE_API_RATELIMIT = True
API_RATELIMIT_PER_MINUTE = 60

# Legal URLs (optional)
LEGAL_PRIVACY_URL = None
LEGAL_TERMS_URL = None
EOF

# Create session directory
mkdir -p /tmp/powerdns-admin-sessions
chown pdnsadmin:pdnsadmin /tmp/powerdns-admin-sessions

# Create a simple initialization script that properly initializes the database and creates admin user
cat > /opt/powerdns-admin/init_db.py << 'EOF'
#!/usr/bin/env python3
import os
import sys

# Monkey patch to disable captcha entirely
import flask_session_captcha
def dummy_init_app(self, app):
    pass
flask_session_captcha.FlaskSessionCaptcha.init_app = dummy_init_app

try:
    from powerdnsadmin import create_app
    from powerdnsadmin.models import db, User, Role
    from werkzeug.security import generate_password_hash
    import time
    
    print("Creating app...")
    app = create_app()
    
    print("Connecting to database...")
    for i in range(30):
        try:
            with app.app_context():
                # Create all tables
                db.create_all()
                print('Database schema created successfully')
                
                # Create Administrator role if it doesn't exist
                admin_role = Role.query.filter_by(name='Administrator').first()
                if not admin_role:
                    admin_role = Role(name='Administrator', description='Administrator role')
                    db.session.add(admin_role)
                    db.session.commit()
                    print('Created Administrator role')
                
                # Check if admin user already exists and remove if corrupted
                admin_username = os.environ.get('ADMIN_USERNAME', 'admin')
                admin_user = User.query.filter_by(username=admin_username).first()
                if admin_user:
                    # Delete existing admin user to recreate with proper password hash
                    db.session.delete(admin_user)
                    db.session.commit()
                    print('Removed existing admin user (corrupted password hash)')
                
                # Create fresh admin user with properly hashed password
                admin_password = generate_password_hash(os.environ.get('ADMIN_PASSWORD', 'admin123'))
                admin_email = os.environ.get('ADMIN_EMAIL', 'admin@local.domain')
                admin_firstname = os.environ.get('ADMIN_FIRSTNAME', 'Admin')
                admin_lastname = os.environ.get('ADMIN_LASTNAME', 'User')
                
                admin_user = User(
                    username=admin_username,
                    password=admin_password,
                    email=admin_email,
                    firstname=admin_firstname,
                    lastname=admin_lastname,
                    role_id=admin_role.id,
                    confirmed=True,
                    otp_secret=None  # Explicitly disable OTP for admin user
                )
                db.session.add(admin_user)
                db.session.commit()
                print('Created fresh admin user:')
                print(f'  Username: {admin_username}')
                print(f'  Password: {os.environ.get("ADMIN_PASSWORD", "admin123")}')
                print(f'  Email: {admin_email}')
                    
                print('Database initialization completed successfully')
            break
        except Exception as e:
            print(f'Database connection failed (attempt {i+1}/30): {e}')
            time.sleep(5)
    else:
        print('Failed to connect to database after 30 attempts')
        sys.exit(1)
        
except Exception as e:
    print(f'Error during initialization: {e}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOF

chmod +x /opt/powerdns-admin/init_db.py

# Initialize database
cd /opt/powerdns-admin
echo "Initializing PowerDNS Admin database..."
python3 init_db.py

# Start the application
echo "Starting PowerDNS-Admin..."
cd /opt/powerdns-admin

# Switch to pdnsadmin user and run the app
su pdnsadmin -s /bin/bash -c "
cd /opt/powerdns-admin

# Disable captcha before importing anything
python3 -c \"
import flask_session_captcha
def dummy_init_app(self, app):
    pass
flask_session_captcha.FlaskSessionCaptcha.init_app = dummy_init_app

# Start the application
import sys
sys.path.insert(0, '/opt/powerdns-admin')

try:
    from powerdnsadmin import create_app
    print('App created successfully')
    
    app = create_app()
    print('Starting server on 0.0.0.0:80')
    app.run(host='0.0.0.0', port=80, debug=True)
except Exception as e:
    print(f'Error starting application: {e}')
    import traceback
    traceback.print_exc()
\"
"
