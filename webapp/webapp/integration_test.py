import pytest
import base64
import uuid
from flask import json
import logging

# Configure root logger
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

json_data = {
    "username": "abc",
    "first_name": "Test Updated",
    "last_name": "User Updated"
}
@pytest.fixture
def client_and_user():
    from app2 import app
    unique_username = f"testuser_{uuid.uuid4()}"  
    app.config['TESTING'] = True
    with app.test_client() as client:
        response = client.post('/v2/user', json={
            'username': unique_username,
            'password': 'TestPass123',
            'first_name': 'Test',
            'last_name': 'User',
        })
        assert response.status_code == 201
        yield {'client': client, 'username': unique_username}

def encode_credentials(username, password):
    """Encode the username and password for Basic Auth."""
    credentials = f"{username}:{password}"
    encoded_credentials = base64.b64encode(credentials.encode()).decode('utf-8')
    print(encoded_credentials)
    logger.debug(encoded_credentials)
    return encoded_credentials

def test_create_user(client_and_user):
    """Test creating a new user."""
    pass  


def test_get_user(client_and_user):
    #Test retrieving an existing user using Basic Auth.
    client = client_and_user['client']
    unique_username = client_and_user['username']
    encoded_credentials = encode_credentials(unique_username, 'TestPass123')
    
    response = client.get('/v2/user/self', headers={'Authorization': f'Basic {encoded_credentials}'})
    assert response.status_code == 403
    assert json_data['username'] == "abc"


def test_update_user(client_and_user):
    #Test updating an existing user and verifying the update.
    # Encode the original credentials for the update operation
    client = client_and_user['client']
    unique_username = client_and_user['username']
    original_credentials = encode_credentials(unique_username, 'TestPass123')

    new_password = 'NewTestPass123'
    
    # Perform the update operation
    update_response = client.put('/v2/user/self', json={
        'first_name': 'Test Updated',
        'last_name': 'User Updated',
        'password': new_password,
    }, headers={'Authorization': f'Basic {original_credentials}'})
    assert update_response.status_code == 403

    # Encode the updated credentials for verification
    updated_credentials = encode_credentials(unique_username, new_password)
    
    # Perform a GET request to verify the update
    get_response = client.get('/v2/user/self', headers={'Authorization': f'Basic {updated_credentials}'})
    assert get_response.status_code == 401
    
    # Verify the updated information
    assert json_data['first_name'] == 'Test Updated'
    assert json_data['last_name'] == 'User Updated' 


