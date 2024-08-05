from flask import Flask, request, jsonify, make_response
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_bcrypt import Bcrypt
from flask_httpauth import HTTPBasicAuth
import uuid
import time
import urllib.parse
import os
from sqlalchemy import text
from datetime import datetime
from flask import current_app
from pythonjsonlogger import jsonlogger
import logging
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler
from google.cloud import pubsub_v1
import json
from google.auth.exceptions import DefaultCredentialsError



app = Flask(__name__)
auth = HTTPBasicAuth()

log_directory = '/var/log/webapp'
log_file = 'app.log'
log_path = os.path.join(log_directory, log_file)

# Ensure the directory exists
#os.makedirs(log_directory, exist_ok=True)

try:
    # Configure logging to file in JSON format
    logHandler = RotatingFileHandler('/var/log/webapp/app.log', maxBytes=10000, backupCount=3)


    # Custom formatter class to include milliseconds and timezone
    class CustomJsonFormatter(jsonlogger.JsonFormatter):
        def add_fields(self, log_record, record, message_dict):
            super(CustomJsonFormatter, self).add_fields(log_record, record, message_dict)
            # Format the timestamp yourself
            now = datetime.utcnow().replace(tzinfo=timezone.utc)
            log_record['timestamp'] = now.strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'


    formatter = CustomJsonFormatter('%(levelname)s %(name)s %(message)s %(asctime)s')

    logHandler.setFormatter(formatter)
    app.logger.addHandler(logHandler)
    app.logger.setLevel(logging.INFO)
except Exception as e:
    print(f"Failed to configure logging: {e}")

try:
    publisher = pubsub_v1.PublisherClient()
    topic_name = 'projects/dev6225webapp/subscriptions/verify-email-subscription'
except DefaultCredentialsError as e:
    # Handle the situation where credentials are not found
    app.logger.error("Google Cloud credentials not found. Ensure the GOOGLE_APPLICATION_CREDENTIALS environment variable is set correctly.")

    # Initialize publisher to None or a mock object if you want to allow the application to run without publishing.
    publisher = None
    topic_name = None

def publish_verification_request(user_email):

    if publisher is None:
        app.logger.warning("Publisher client is not initialized. Skipping message publish.")
        return

    message_json = json.dumps({
        'email': user_email,
    })
    message_bytes = message_json.encode('utf-8')
    
    # Publish the message
    
    try:
        future = publisher.publish(topic_name, data=message_bytes)
        # Wait for the publish call to return and get the message ID
        message_id = future.result()
        print(f"Message published with ID: {message_id}")
    except Exception as e:
        print(f"An exception occurred while publishing: {e}")



def load_database_uri(ini_file_path='/opt/csye6225/db_properties.ini'):
    try:
        with open(ini_file_path, 'r') as file:
            for line in file:
                line = line.strip()
                if line.startswith('SQLALCHEMY_DATABASE_URI'):
                    return line.split('=')[1]  # Extract the URI part
    except FileNotFoundError:
        # Handle the error or log it if the file does not exist
        print(f"File {ini_file_path} not found.")
    return None

# Load database configurations from the INI file
database_uri = load_database_uri()
if database_uri:
    app.config['SQLALCHEMY_DATABASE_URI'] = database_uri
else:
    # Fallback to a default value or handle the error appropriately
    app.config['SQLALCHEMY_DATABASE_URI'] = 'mysql+pymysql://root:root@localhost/Users'


# Load database configurations from environment variables
#app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('SQLALCHEMY_DATABASE_URI', 'mysql+pymysql://root:root@localhost/Users')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)
migrate = Migrate(app, db)
bcrypt = Bcrypt(app)

class User(db.Model):
    __tablename__ = 'user'
    id = db.Column(db.String(36), primary_key=True)
    first_name = db.Column(db.String(255), nullable=False)
    last_name = db.Column(db.String(255), nullable=False)
    username = db.Column(db.String(255), unique=True, nullable=False)
    password = db.Column(db.String(255), nullable=False)
    account_created = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    account_updated = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)
    verified = db.Column(db.Boolean, default=False, nullable=False)

@auth.verify_password
def verify_password(username, password):
    current_app.logger.debug(f"Authenticating user: {username}")
    current_app.logger.debug(f"Authenticating password: {password}")
    user = User.query.filter_by(username=username).first()
    if user and bcrypt.check_password_hash(user.password, password):
        return username

@app.route('/v2/user', methods=['POST'])
def create_user():
    data = request.json
    app.logger.info('Received request for user creation', extra={'request_data': data})
    username = data['username']
    print()
    if request.args:
        app.logger.warning('Unexpected query parameters in user creation request')
        return make_response('', 400, {'Cache-Control': 'no-cache'})

    if User.query.filter_by(username=username).first():
        app.logger.error('Attempt to create an existing user', extra={'username': data['username']})
        return make_response(jsonify({"error": "User already exists"}), 400, {'Cache-Control': 'no-cache'})
    
    hashed_password = bcrypt.generate_password_hash(data['password']).decode('utf-8')
    user = User(
        id=str(uuid.uuid4()),
        first_name=data['first_name'],
        last_name=data['last_name'],
        username=username,
        password=hashed_password
    )
    db.session.add(user)
    db.session.commit()
    app.logger.info('User created successfully', extra={'user_id': user.id, 'username': user.username})
    publish_verification_request(user.username)
    return jsonify({
        "id": user.id,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "username": user.username,
        "account_created": user.account_created.isoformat() + 'Z',
        "account_updated": user.account_updated.isoformat() + 'Z'
    }), 201


@app.route('/v2/user/self', methods=['PUT'])
@auth.login_required
def update_user():
    data = request.json
    username = auth.current_user()
    app.logger.info('Received get request for user', extra={'username': username})
    user = User.query.filter_by(username=username).first()
    if request.args:
        app.logger.warning('Illegal put request arguments')
        return make_response('', 400, {'Cache-Control': 'no-cache'})

    if not user:
        return make_response(jsonify({"error": "User not found"}), 404, {'Cache-Control': 'no-cache'})
    
    if not user.verified:
        app.logger.error('User account not verified')
        return make_response(jsonify({"error": "User account not verified."})), 403  # HTTP 403 Forbidden
    
    if 'first_name' in data:
        user.first_name = data['first_name']
    if 'last_name' in data:
        user.last_name = data['last_name']
    if 'password' in data:
        user.password = bcrypt.generate_password_hash(data['password']).decode('utf-8')
    else:
        app.logger.info('Illegal Put request, missing required fields')
        return make_response(jsonify({"error": "Bad Request. Missing required fields."}), 400, {'Cache-Control': 'no-cache'})

    user.account_updated = datetime.utcnow()
    db.session.commit()
    app.logger.info('User updated successfully', extra={'username': username})
    
    return '', 204



@app.route('/v2/user/self', methods=['GET'])
@auth.login_required
def get_user():
    username = auth.current_user()
    user = User.query.filter_by(username=username).first()

    # check for query params
    if request.args:
        app.logger.warning('Illegal get request arguments')
        return make_response('', 503, {'Cache-Control': 'no-cache'})

    if not user.verified:
        app.logger.error('User account not verified')
        return make_response(jsonify({"error": "User account not verified."})), 403  
    
    if user:
        user_data = {
            "id": user.id,
            "first_name": user.first_name,
            "last_name": user.last_name,
            "username": user.username,
            "account_created": user.account_created.isoformat() + 'Z',
            "account_updated": user.account_updated.isoformat() + 'Z'
        }
        app.logger.info('Received get request for user', extra={'username': username})
        return jsonify(user_data), 200
    else:
        app.logger.error('Illegal get request for user')
        return make_response(jsonify({"error": "User not found"}), 404, {'Cache-Control': 'no-cache'})

# Public end points: Operations available to all users without authentication 
@app.route('/healthz', methods=['GET'])
def health_end_point():

    app.logger.info('API Request Received', extra={'path': request.path, 'method': request.method})
    # check for query params
    if request.args:

        app.logger.info('Illegal Health check arguments')
        return make_response('', 503, {'Cache-Control': 'no-cache'})
    # check if payload (payload not allowed)
    if request.get_data():
        app.logger.info('Illegal Health check endpoint payload')
        return make_response('', 503, {'Cache-Control': 'no-cache'})

    try:
        # check connection with database
        db.session.execute(text('SELECT * from user'))
        db.session.commit()
        app.logger.info('Health check passed')
        return make_response('', 200, {'Cache-Control': 'no-cache'})

    except Exception as e:
        app.logger.info('Illegal Health check endpoint/request method')
        return make_response('', 503, {'Cache-Control': 'no-cache'})
   
@app.route('/healthz', methods=['POST'])   
def health_post_end_point():
    app.logger.error('Illegal Health check endpoint/request method')
    return make_response('', 405, {'Cache-Control': 'no-cache'})

@app.route('/healthz', methods=['PUT'])   
def health_put_end_point():
    app.logger.error('Illegal Health check endpoint/request method')
    return make_response('', 405, {'Cache-Control': 'no-cache'})

@app.route('/healthz', methods=['DELETE'])   
def health_delete_end_point():
    app.logger.info('Illegal Health check endpoint/request method')
    return make_response('', 405, {'Cache-Control': 'no-cache'})

@app.route('/healthz', methods=['HEAD'])   
def health_head_end_point():
    app.logger.info('Illegal Health check endpoint/request method')
    return make_response('', 405, {'Cache-Control': 'no-cache'})

@app.route('/healthz', methods=['OPTIONS'])   
def health_options_end_point():
    app.logger.info('Illegal Health check endpoint/request method')
    return make_response('', 405, {'Cache-Control': 'no-cache'})


@app.route('/verify', methods=['GET'])
def verify_email():
    token = request.args.get('token')
    email = urllib.parse.unquote(request.args.get('email'))
    expires_str = urllib.parse.unquote(request.args.get('expires'))
    expires = datetime.fromisoformat(expires_str)

    if datetime.utcnow() > expires:
        app.logger.warning('verification link expired')
        return make_response(jsonify({"error": "This verification link has expired."})), 400

    user = User.query.filter_by(username=email).first()
    if not user:
        app.logger.warning('Email not found, username does not exist')
        return make_response(jsonify({"error": "Email not found, username does not exist."})), 404

    # Check if the user is already verified
    if user.verified:
        app.logger.info('User account is already verified')
        return make_response(jsonify({"message": "User account is already verified."})), 200

    if user:  
        user.verified = True
        db.session.commit()
        app.logger.info('Email verified successfully')
        return make_response(jsonify({"message": "Email verified successfully!"})), 200
    else:
        app.logger.warning('Invalid verification link.')
        return make_response(jsonify({"error": "Invalid verification link."})), 400



def protected_endpoint():
    username = auth.current_user()
    user = User.query.filter_by(username=username).first()
    if not user.verified:
        return jsonify({"error": "User account not verified."}), 403  # HTTP 403 Forbidden
    # Proceed with endpoint logic


if __name__ == '__main__':
    app.run(host='0.0.0.0',port= 8080, debug=True)
