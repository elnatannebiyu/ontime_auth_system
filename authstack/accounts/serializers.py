from django.contrib.auth.models import User
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

class MeSerializer(serializers.ModelSerializer):
    roles = serializers.SerializerMethodField()
    permissions = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ["id", "username", "email", "first_name", "last_name", "roles", "permissions"]

    def get_roles(self, obj):
        return list(obj.groups.values_list("name", flat=True))

    def get_permissions(self, obj):
        # Effective permissions, including those from groups
        return sorted(list(obj.get_all_permissions()))

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
