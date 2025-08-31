import jwt
import requests
import json
from datetime import datetime, timedelta
from django.conf import settings
from django.utils import timezone
from typing import Dict, Tuple, Optional
import logging

logger = logging.getLogger(__name__)

class SocialAuthService:
    """Handle social authentication providers"""
    
    @staticmethod
    def verify_google_token(id_token: str) -> Tuple[bool, Dict]:
        """Verify Google ID token"""
        try:
            # Decode without verification first to get kid
            unverified = jwt.decode(id_token, options={"verify_signature": False})
            
            # Get Google's public keys
            response = requests.get('https://www.googleapis.com/oauth2/v3/certs')
            keys = response.json()['keys']
            
            # Find the key with matching kid
            header = jwt.get_unverified_header(id_token)
            key = next((k for k in keys if k['kid'] == header['kid']), None)
            
            if not key:
                return False, {'error': 'Invalid key ID'}
            
            # Convert JWK to PEM format
            from jwt.algorithms import RSAAlgorithm
            public_key = RSAAlgorithm.from_jwk(json.dumps(key))
            
            # Verify token
            decoded = jwt.decode(
                id_token,
                public_key,
                algorithms=['RS256'],
                audience=settings.GOOGLE_CLIENT_ID,
                issuer=['accounts.google.com', 'https://accounts.google.com']
            )
            
            # Extract user info
            user_info = {
                'provider_id': decoded['sub'],
                'email': decoded.get('email'),
                'email_verified': decoded.get('email_verified', False),
                'name': decoded.get('name'),
                'picture': decoded.get('picture'),
                'given_name': decoded.get('given_name'),
                'family_name': decoded.get('family_name'),
            }
            
            return True, user_info
            
        except jwt.ExpiredSignatureError:
            return False, {'error': 'Token expired'}
        except jwt.InvalidTokenError as e:
            return False, {'error': f'Invalid token: {str(e)}'}
        except Exception as e:
            logger.error(f"Google token verification failed: {e}")
            return False, {'error': 'Verification failed'}
    
    @staticmethod
    def verify_apple_token(id_token: str, nonce: str = None) -> Tuple[bool, Dict]:
        """Verify Apple ID token"""
        try:
            # Get Apple's public keys
            response = requests.get('https://appleid.apple.com/auth/keys')
            keys = response.json()['keys']
            
            # Get the matching key
            header = jwt.get_unverified_header(id_token)
            key = next((k for k in keys if k['kid'] == header['kid']), None)
            
            if not key:
                return False, {'error': 'Invalid key ID'}
            
            # Convert to PEM format
            from jwt.algorithms import RSAAlgorithm
            public_key = RSAAlgorithm.from_jwk(json.dumps(key))
            
            # Verify token
            decoded = jwt.decode(
                id_token,
                public_key,
                algorithms=['RS256'],
                audience=settings.APPLE_CLIENT_ID,
                issuer='https://appleid.apple.com'
            )
            
            # Verify nonce if provided
            if nonce and decoded.get('nonce') != nonce:
                return False, {'error': 'Invalid nonce'}
            
            # Extract user info
            user_info = {
                'provider_id': decoded['sub'],
                'email': decoded.get('email'),
                'email_verified': decoded.get('email_verified', False),
                'is_private_email': decoded.get('is_private_email', False),
            }
            
            return True, user_info
            
        except jwt.ExpiredSignatureError:
            return False, {'error': 'Token expired'}
        except jwt.InvalidTokenError as e:
            return False, {'error': f'Invalid token: {str(e)}'}
        except Exception as e:
            logger.error(f"Apple token verification failed: {e}")
            return False, {'error': 'Verification failed'}
