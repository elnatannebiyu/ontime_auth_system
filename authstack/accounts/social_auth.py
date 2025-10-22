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
            logger.debug("[GoogleAuth] Received ID token (unverified) with claims keys=%s", list(unverified.keys()))
            # Surface critical claims for diagnosis
            try:
                logger.info(
                    "[GoogleAuth] Token claims (unverified): aud=%s azp=%s iss=%s sub=%s email=%s",
                    unverified.get('aud'), unverified.get('azp'), unverified.get('iss'),
                    unverified.get('sub'), unverified.get('email')
                )
            except Exception:
                pass
            
            # Use PyJWT's JWK client to resolve the correct signing key
            jwks_url = 'https://www.googleapis.com/oauth2/v3/certs'
            header = jwt.get_unverified_header(id_token)
            logger.debug("[GoogleAuth] Token header kid=%s alg=%s", header.get('kid'), header.get('alg'))
            try:
                jwk_client = jwt.PyJWKClient(jwks_url)
                signing_key = jwk_client.get_signing_key_from_jwt(id_token)
                public_key = signing_key.key
            except Exception as e:
                logger.warning("[GoogleAuth] Failed to obtain signing key from JWKs: %s", e)
                return False, {'error': 'Verification failed'}
            
            # Build list of allowed audiences (client IDs) to support both Web and iOS clients
            allowed_audiences = []
            # New: allow specifying a set of web client IDs explicitly
            web_ids = getattr(settings, 'GOOGLE_WEB_CLIENT_IDS', None)
            if isinstance(web_ids, (list, tuple, set)):
                allowed_audiences.extend([x for x in web_ids if x])
            elif isinstance(web_ids, str) and web_ids.strip():
                allowed_audiences.extend([x.strip() for x in web_ids.split(',') if x.strip()])
            if getattr(settings, 'GOOGLE_CLIENT_ID', ''):
                allowed_audiences.append(settings.GOOGLE_CLIENT_ID)
            extra = getattr(settings, 'GOOGLE_ADDITIONAL_CLIENT_IDS', [])
            if isinstance(extra, (list, tuple)):
                allowed_audiences.extend([x for x in extra if x])
            elif isinstance(extra, str) and extra.strip():
                # Allow comma-separated string fallback
                allowed_audiences.extend([x.strip() for x in extra.split(',') if x.strip()])
            logger.info("[GoogleAuth] Allowed audiences (client IDs)=%s", allowed_audiences)

            # Verify token (PyJWT accepts audience as a list)
            decoded = jwt.decode(
                id_token,
                public_key,
                algorithms=['RS256'],
                audience=allowed_audiences if allowed_audiences else None,
                issuer=['accounts.google.com', 'https://accounts.google.com']
            )
            logger.debug(
                "[GoogleAuth] Verification success sub=%s aud=%s email_verified=%s",
                decoded.get('sub'), decoded.get('aud'), decoded.get('email_verified')
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
            logger.warning("[GoogleAuth] Token expired")
            return False, {'error': 'Token expired'}
        except jwt.InvalidTokenError as e:
            logger.warning("[GoogleAuth] Invalid token: %s", e)
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
