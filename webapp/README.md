# webapp

### Application  - Flask-based RESTful API with basic authentication. The API allows users to create, retrieve, and update user information. Additionally, it provides health check endpoints.

Dependencies
Flask: Web framework for Python.
Flask-SQLAlchemy: Flask extension for SQL database integration.
Flask-Migrate: Flask extension for database migrations.
Flask-Bcrypt: Flask extension for password hashing.
Flask-HTTPAuth: Flask extension for HTTP basic authentication.
MySQL: Relational database management system.

Setup
Install dependencies:
pip install Flask Flask-SQLAlchemy Flask-Migrate Flask-Bcrypt Flask-HTTPAuth

Clone the repository:
git clone <repository-url>

Navigate to the project directory:
cd <project-directory>

Ensure MySQL database is set up and configured correctly. Update the SQLALCHEMY_DATABASE_URI in app.py accordingly.
Run these commands to initialize the db
flask db init
flask db migrate -m "Initial migration."
flask db upgrade

Run the Flask application:
python app.py

Endpoints
Create User:
Endpoint: POST /v1/user
Creates a new user with provided details.

Update User:
Endpoint: PUT /v1/user/self
Updates the details of the currently authenticated user.

Get User:
Endpoint: GET /v1/user/self
Retrieves the details of the currently authenticated user.

Health Check:
Endpoint: GET /healthz
Health check endpoint to verify the application's status.

Authentication
Basic Authentication is used to secure the /v1/user/self endpoints.
User credentials are stored securely in the database using hashed passwords.

### Testing with pytest
Unit tests for each endpoint and utility functions can be written using pytest.

Dependencies
pytest: Testing framework for Python.
flask: Web framework for Python.
base64: Encoding and decoding utilities.
uuid: Generation of unique identifiers.
json: JSON handling in Python.
logging: Logging utilities for debugging.
Setup
Install dependencies:

pip install pytest flask
Clone the repository:

git clone <repository-url>
Navigate to the project directory:

cd <project-directory>
Running Tests
To run the tests, execute the following command:

pytest
This command will execute all test cases defined in the test_*.py files within the project directory.

Structure
app2.py: Flask application file containing the API endpoints.
tests/: Directory containing test files.
test_app2.py: Test cases for the Flask application.

Test Cases
Creating a User (test_create_user):
Tests the creation of a new user via a POST request to /v1/user.

Retrieving a User (test_get_user):
Tests retrieving an existing user using Basic Authentication via a GET request to /v1/user/self.

Updating a User (test_update_user):
Tests updating an existing user's information via a PUT request to /v1/user/self.

Fixtures
client_and_user: Fixture to set up the Flask test client and create a new unique user for testing purposes.

Utility Functions
encode_credentials: Encodes the username and password for Basic Authentication.

Usage
Run the tests to ensure the Flask API functions correctly.
Modify and expand the test cases as necessary to cover more scenarios and endpoints.

Configuring the environment file for db connection using resource:
https://dev.to/sasicodes/flask-and-env-22am
https://stackoverflow.com/questions/54566480/how-to-read-a-file-in-python-flask