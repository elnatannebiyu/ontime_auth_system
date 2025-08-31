from typing import Dict, List, Any
from enum import Enum
from django.utils import timezone


class FieldType(str, Enum):
    TEXT = "text"
    EMAIL = "email"
    PASSWORD = "password"
    PHONE = "phone"
    SELECT = "select"
    CHECKBOX = "checkbox"
    DATE = "date"
    OTP = "otp"
    HIDDEN = "hidden"


class ValidationRule(str, Enum):
    REQUIRED = "required"
    MIN_LENGTH = "min_length"
    MAX_LENGTH = "max_length"
    PATTERN = "pattern"
    EMAIL = "email"
    PHONE = "phone"
    MATCH_FIELD = "match_field"
    UNIQUE = "unique"
    STRONG_PASSWORD = "strong_password"


class FormAction(str, Enum):
    """Form action types"""
    LOGIN = "login"
    REGISTER = "register"
    RESET_PASSWORD = "reset_password"
    VERIFY_EMAIL = "verify_email"
    VERIFY_PHONE = "verify_phone"
    VERIFY_OTP = "verify_otp"
    UPDATE_PROFILE = "update_profile"


class DynamicFormSchema:
    """Define dynamic form schemas for different auth flows"""
    
    @classmethod
    def get_login_schema(cls) -> Dict[str, Any]:
        """Get login form schema"""
        return {
            "form_id": "login_form",
            "title": "Sign In",
            "description": "Enter your credentials to continue",
            "action": FormAction.LOGIN,
            "submit_button": {
                "text": "Sign In",
                "loading_text": "Signing in..."
            },
            "fields": [
                {
                    "name": "username",
                    "type": FieldType.TEXT,
                    "label": "Email or Username",
                    "placeholder": "Enter email or username",
                    "icon": "person",
                    "required": True,
                    "autofocus": True,
                    "validation": [
                        {"rule": ValidationRule.REQUIRED, "message": "Username is required"},
                        {"rule": ValidationRule.MIN_LENGTH, "value": 3, "message": "Minimum 3 characters"}
                    ]
                },
                {
                    "name": "password",
                    "type": FieldType.PASSWORD,
                    "label": "Password",
                    "placeholder": "Enter password",
                    "icon": "lock",
                    "required": True,
                    "show_toggle": True,
                    "validation": [
                        {"rule": ValidationRule.REQUIRED, "message": "Password is required"}
                    ]
                },
                {
                    "name": "remember_me",
                    "type": FieldType.CHECKBOX,
                    "label": "Remember me",
                    "default_value": False
                }
            ],
            "links": [
                {"text": "Forgot password?", "action": "forgot_password", "align": "right"},
                {"text": "Don't have an account? Sign up", "action": "register", "align": "center"}
            ],
            "social_auth": {
                "enabled": True,
                "providers": ["google", "apple", "facebook"],
                "divider_text": "Or continue with"
            }
        }
    
    @classmethod
    def get_register_schema(cls, require_phone: bool = False) -> Dict[str, Any]:
        """Get registration form schema"""
        fields = [
            {
                "name": "email",
                "type": FieldType.EMAIL,
                "label": "Email Address",
                "placeholder": "your@email.com",
                "icon": "email",
                "required": True,
                "autofocus": True,
                "validation": [
                    {"rule": ValidationRule.REQUIRED, "message": "Email is required"},
                    {"rule": ValidationRule.EMAIL, "message": "Invalid email format"},
                    {"rule": ValidationRule.UNIQUE, "model": "User", "field": "email", "message": "Email already registered"}
                ]
            },
            {
                "name": "username",
                "type": FieldType.TEXT,
                "label": "Username",
                "placeholder": "Choose a username",
                "icon": "person",
                "required": True,
                "hint": "3-20 characters, letters, numbers, and underscores only",
                "validation": [
                    {"rule": ValidationRule.REQUIRED, "message": "Username is required"},
                    {"rule": ValidationRule.MIN_LENGTH, "value": 3, "message": "Minimum 3 characters"},
                    {"rule": ValidationRule.MAX_LENGTH, "value": 20, "message": "Maximum 20 characters"},
                    {"rule": ValidationRule.PATTERN, "value": "^[a-zA-Z0-9_]+$", "message": "Only letters, numbers, and underscores"},
                    {"rule": ValidationRule.UNIQUE, "model": "User", "field": "username", "message": "Username taken"}
                ]
            }
        ]
        
        if require_phone:
            fields.append({
                "name": "phone",
                "type": FieldType.PHONE,
                "label": "Phone Number",
                "placeholder": "+1234567890",
                "icon": "phone",
                "required": True,
                "country_code": "US",
                "validation": [
                    {"rule": ValidationRule.REQUIRED, "message": "Phone number is required"},
                    {"rule": ValidationRule.PHONE, "message": "Invalid phone number"},
                    {"rule": ValidationRule.UNIQUE, "model": "User", "field": "phone_e164", "message": "Phone already registered"}
                ]
            })
        
        fields.extend([
            {
                "name": "password",
                "type": FieldType.PASSWORD,
                "label": "Password",
                "placeholder": "Create a strong password",
                "icon": "lock",
                "required": True,
                "show_toggle": True,
                "show_strength": True,
                "hint": "8+ characters with uppercase, lowercase, number, and symbol",
                "validation": [
                    {"rule": ValidationRule.REQUIRED, "message": "Password is required"},
                    {"rule": ValidationRule.MIN_LENGTH, "value": 8, "message": "Minimum 8 characters"},
                    {"rule": ValidationRule.STRONG_PASSWORD, "message": "Password too weak"}
                ]
            },
            {
                "name": "confirm_password",
                "type": FieldType.PASSWORD,
                "label": "Confirm Password",
                "placeholder": "Re-enter password",
                "icon": "lock_outline",
                "required": True,
                "show_toggle": True,
                "validation": [
                    {"rule": ValidationRule.REQUIRED, "message": "Please confirm password"},
                    {"rule": ValidationRule.MATCH_FIELD, "field": "password", "message": "Passwords don't match"}
                ]
            },
            {
                "name": "terms",
                "type": FieldType.CHECKBOX,
                "label": "I agree to the Terms of Service and Privacy Policy",
                "required": True,
                "validation": [
                    {"rule": ValidationRule.REQUIRED, "message": "You must accept the terms"}
                ]
            }
        ])
        
        return {
            "form_id": "register_form",
            "title": "Create Account",
            "description": "Join us today",
            "action": FormAction.REGISTER,
            "submit_button": {
                "text": "Create Account",
                "loading_text": "Creating account..."
            },
            "fields": fields,
            "links": [
                {"text": "Already have an account? Sign in", "action": "login", "align": "center"}
            ],
            "social_auth": {
                "enabled": True,
                "providers": ["google", "apple", "facebook"],
                "divider_text": "Or sign up with"
            }
        }
    
    @classmethod
    def get_otp_verification_schema(cls, destination_type: str = "email") -> Dict[str, Any]:
        """Get OTP verification form schema"""
        return {
            "form_id": "otp_verification",
            "title": f"Verify Your {destination_type.title()}",
            "description": f"We've sent a code to your {destination_type}",
            "action": FormAction.VERIFY_EMAIL if destination_type == "email" else FormAction.VERIFY_PHONE,
            "submit_button": {
                "text": "Verify",
                "loading_text": "Verifying..."
            },
            "fields": [
                {
                    "name": "otp_code",
                    "type": FieldType.OTP,
                    "label": "Verification Code",
                    "placeholder": "000000",
                    "length": 6,
                    "numeric_only": True,
                    "autofocus": True,
                    "auto_submit": True,
                    "validation": [
                        {"rule": ValidationRule.REQUIRED, "message": "Code is required"},
                        {"rule": ValidationRule.MIN_LENGTH, "value": 6, "message": "Enter 6 digits"},
                        {"rule": ValidationRule.MAX_LENGTH, "value": 6, "message": "Enter 6 digits"}
                    ]
                }
            ],
            "resend": {
                "enabled": True,
                "cooldown": 60,
                "text": "Didn't receive code?",
                "button_text": "Resend Code"
            },
            "timer": {
                "enabled": True,
                "duration": 300,
                "message": "Code expires in {time}"
            }
        }
