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
    import bcrypt
    import time
    
    print("Creating app...")
    app = create_app(config='/etc/powerdns-admin/production_config.py')
    
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
                    print('Removed existing admin user (for fresh creation)')
                
                # Create fresh admin user with properly hashed password using bcrypt
                admin_password_plain = os.environ.get('ADMIN_PASSWORD', 'admin123')
                admin_password_hash = bcrypt.hashpw(admin_password_plain.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
                admin_email = os.environ.get('ADMIN_EMAIL', 'admin@local.domain')
                admin_firstname = os.environ.get('ADMIN_FIRSTNAME', 'Admin')
                admin_lastname = os.environ.get('ADMIN_LASTNAME', 'User')
                
                admin_user = User(
                    username=admin_username,
                    password=admin_password_hash,
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
                print(f'  Password: {admin_password_plain}')
                print(f'  Email: {admin_email}')
                    
                print('Database initialization completed successfully')
                break
        except Exception as e:
            print(f'Database connection attempt {i+1}/30 failed: {e}')
            if i < 29:
                time.sleep(2)
            else:
                raise
                
except Exception as e:
    print(f'Database initialization failed: {e}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
