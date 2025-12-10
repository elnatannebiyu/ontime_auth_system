from django.contrib.auth.models import User, Permission
from django.db.models import Q
from rest_framework import serializers
from django.contrib.auth.password_validation import validate_password
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from .validators import validate_email_domain, sanitize_input
from .models import Membership

class MeSerializer(serializers.ModelSerializer):
    roles = serializers.SerializerMethodField()
    tenant_roles = serializers.SerializerMethodField()
    permissions = serializers.SerializerMethodField()
    email_verified = serializers.SerializerMethodField()
    has_password = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            "username",
            "email",
            "email_verified",
            "has_password",
            "first_name",
            "last_name",
            "roles",          # global groups
            "tenant_roles",   # per-tenant roles from Membership
            "permissions",
        ]

    def get_roles(self, obj):
        return list(obj.groups.values_list("name", flat=True))

    def get_permissions(self, obj):
        # Effective permissions including global groups and per-tenant Membership roles
        perms = set(obj.get_all_permissions())
        # If request has a tenant, merge in permissions from Membership.roles
        request = self.context.get("request") if hasattr(self, "context") else None
        tenant = getattr(request, "tenant", None) if request is not None else None
        if tenant is not None:
            from .models import Membership
            member = Membership.objects.filter(user=obj, tenant=tenant).first()
            if member:
                role_perms = Permission.objects.filter(group__in=member.roles.all())
                # Permission.__str__ is app_label | codename; we want "app_label.codename"
                # get_all_permissions returns strings in format "app_label.codename"
                perms.update({f"{p.content_type.app_label}.{p.codename}" for p in role_perms})
        return sorted(list(perms))

    def get_tenant_roles(self, obj):
        # Resolve per-tenant roles for the current request. If no tenant, return [].
        request = self.context.get("request") if hasattr(self, "context") else None
        tenant = getattr(request, "tenant", None) if request is not None else None
        if not tenant:
            return []
        member = Membership.objects.filter(user=obj, tenant=tenant).first()
        if not member:
            return []
        return list(member.roles.values_list("name", flat=True))

    def get_email_verified(self, obj):
        """Return whether this user's email has been verified.

        Uses the related UserProfile if present; falls back to False if no
        profile exists so the API is stable even for legacy users.
        """
        try:
            profile = getattr(obj, "profile", None)
            if profile is None:
                return False
            val = getattr(profile, "email_verified", False)
            return bool(val)
        except Exception:
            return False

    def get_has_password(self, obj):
        """Return whether this user has a usable password set.

        This mirrors Django's has_usable_password() helper and allows the
        frontend to decide whether to show enable/disable password actions
        in the profile UI.
        """
        try:
            return bool(obj.has_usable_password())
        except Exception:
            return False

class CookieTokenObtainPairSerializer(TokenObtainPairSerializer):
    """Inject roles/perms into **access** token for UI hints."""
    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        # Add claims for UI (never trust these on backend)
        token["roles"] = list(user.groups.values_list("name", flat=True))
        # Effective permissions, including group-derived ones
        token["perms"] = sorted(list(user.get_all_permissions()))
        token["username"] = user.username
        return token

    def validate(self, attrs):
        """Override to inject tenant context into token claims before signing."""
        data = super().validate(attrs)

        request = self.context.get("request")
        tenant = getattr(request, "tenant", None) if request is not None else None
        if tenant is not None and hasattr(self, "user") and self.user is not None:
            # Rebuild tokens so we can include tenant claims before stringifying
            refresh = self.get_token(self.user)

            # Add tenant-aware claims to access token
            access = refresh.access_token
            access["tenant_id"] = tenant.slug
            # per-tenant roles via Membership
            member = Membership.objects.filter(user=self.user, tenant=tenant).first()
            tenant_roles = []
            if member:
                tenant_roles = list(member.roles.values_list("name", flat=True))
            access["tenant_roles"] = tenant_roles

            data = {"refresh": str(refresh), "access": str(access)}
        return data


class RegistrationSerializer(serializers.Serializer):
    email = serializers.EmailField(validators=[validate_email_domain])
    password = serializers.CharField(write_only=True, min_length=8)
    
    def validate_password(self, value):
        """Validate password strength"""
        validate_password(value)
        return value
    
    def validate_email(self, value):
        """Additional email validation and sanitization"""
        value = value.lower().strip()
        validate_email_domain(value)
        # Enforce case-insensitive uniqueness across both username and email
        if User.objects.filter(Q(username__iexact=value) | Q(email__iexact=value)).exists():
            raise serializers.ValidationError("A user with this email already exists.")
        return value

    def create_user(self):
        email = self.validated_data["email"].lower()
        password = self.validated_data["password"]
        user = User.objects.create_user(username=email, email=email, password=password)
        return user


class UserAdminSerializer(serializers.ModelSerializer):
    groups = serializers.SlugRelatedField(many=True, read_only=True, slug_field='name')
    tenant_roles = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'first_name', 'last_name',
            'is_active', 'is_superuser', 'last_login', 'date_joined', 'groups', 'tenant_roles'
        ]
        read_only_fields = ['id', 'username', 'is_superuser', 'last_login', 'date_joined', 'groups']

    def validate_email(self, value):
        v = (value or '').lower().strip()
        if not v:
            raise serializers.ValidationError('Email is required')
        # Ensure unique across username/email
        qs = User.objects.filter(Q(username__iexact=v) | Q(email__iexact=v))
        if self.instance:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError('A user with this email already exists.')
        return v

    def get_tenant_roles(self, obj):
        request = getattr(self, 'context', {}).get('request') if hasattr(self, 'context') else None
        tenant = getattr(request, 'tenant', None) if request is not None else None
        if tenant is None:
            return []
        member = Membership.objects.filter(user=obj, tenant=tenant).first()
        if not member:
            return []
        return list(member.roles.values_list('name', flat=True))
