from django.contrib.auth.models import User
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from .models import Membership

class MeSerializer(serializers.ModelSerializer):
    roles = serializers.SerializerMethodField()
    tenant_roles = serializers.SerializerMethodField()
    permissions = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            "id",
            "username",
            "email",
            "first_name",
            "last_name",
            "roles",          # global groups
            "tenant_roles",   # per-tenant roles from Membership
            "permissions",
        ]

    def get_roles(self, obj):
        return list(obj.groups.values_list("name", flat=True))

    def get_permissions(self, obj):
        # Effective permissions, including those from groups
        return sorted(list(obj.get_all_permissions()))

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
    email = serializers.EmailField()
    password = serializers.CharField(min_length=8, write_only=True)

    def validate_email(self, value):
        if User.objects.filter(username=value).exists():
            raise serializers.ValidationError("A user with this email already exists.")
        return value

    def create_user(self):
        email = self.validated_data["email"].lower()
        password = self.validated_data["password"]
        user = User.objects.create_user(username=email, email=email, password=password)
        return user
