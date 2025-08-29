from django.test import TestCase
from django.urls import reverse
from django.contrib.auth.models import User
from rest_framework.test import APIClient
from tenants.models import Tenant
from rest_framework_simplejwt.tokens import RefreshToken


class MeEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.tenant = Tenant.objects.create(slug="ontime", name="Ontime")
        # Useful URLs
        self.url_token = "/api/token/"
        self.url_me = "/api/me/"

    def create_user(self, email="user@example.com", password="p@ssw0rd!123"):
        return User.objects.create_user(username=email, email=email, password=password)

    def obtain_token(self, email, password, with_tenant_header=True):
        headers = {}
        if with_tenant_header:
            headers["HTTP_X_TENANT_ID"] = self.tenant.slug
        resp = self.client.post(self.url_token, {"username": email, "password": password}, format="json", **headers)
        self.assertEqual(resp.status_code, 200)
        return resp.data["access"]

    def make_token_without_tenant(self, user):
        """Create a JWT access token for a user WITHOUT tenant_id claim.

        We bypass the HTTP token endpoint because middleware requires X-Tenant-Id
        there. Using SimpleJWT directly mimics a client presenting a token that
        lacks tenant context.
        """
        refresh = RefreshToken.for_user(user)
        access = refresh.access_token
        # Ensure no tenant_id is set
        access.payload.pop("tenant_id", None)
        return str(access)

    def test_401_when_no_authorization_header(self):
        # Arrange: have a tenant resolved but no Authorization
        headers = {"HTTP_X_TENANT_ID": self.tenant.slug}
        # Act
        resp = self.client.get(self.url_me, **headers)
        # Assert
        self.assertEqual(resp.status_code, 401)
        self.assertIn("Authentication credentials were not provided", resp.data.get("detail", ""))

    def test_400_when_missing_tenant_header(self):
        # Arrange: authenticated but no tenant header on localhost
        user = self.create_user()
        token = self.obtain_token(user.username, "p@ssw0rd!123", with_tenant_header=True)
        # Act: Call /api/me/ without X-Tenant-Id
        resp = self.client.get(self.url_me, HTTP_AUTHORIZATION=f"Bearer {token}")
        # Assert
        self.assertEqual(resp.status_code, 400)
        body = resp.json()
        self.assertIn("Unknown tenant", body.get("detail", ""))

    def test_403_when_token_missing_tenant_id(self):
        # Arrange: create an access token that lacks tenant_id claim
        user = self.create_user("no-tenant@example.com")
        token = self.make_token_without_tenant(user)
        # Act: Call /api/me/ WITH tenant header so request resolves a tenant
        resp = self.client.get(self.url_me, HTTP_AUTHORIZATION=f"Bearer {token}", HTTP_X_TENANT_ID=self.tenant.slug)
        # Assert
        self.assertEqual(resp.status_code, 403)
        self.assertIn("Token missing tenant context", resp.json().get("detail", ""))

    def test_403_when_not_a_member_of_tenant(self):
        # Arrange: token WITH tenant_id claim but user has NO membership
        user = self.create_user("nomember@example.com")
        token = self.obtain_token(user.username, "p@ssw0rd!123", with_tenant_header=True)
        # Act
        resp = self.client.get(self.url_me, HTTP_AUTHORIZATION=f"Bearer {token}", HTTP_X_TENANT_ID=self.tenant.slug)
        # Assert
        self.assertEqual(resp.status_code, 403)
        self.assertIn("Not a member of this tenant", resp.data.get("detail", ""))

    def test_200_success_when_member_and_matching_tenant(self):
        # Arrange: create user + membership and obtain tenant-aware token
        user = self.create_user("member@example.com")
        # Create membership
        from accounts.models import Membership
        Membership.objects.create(user=user, tenant=self.tenant)
        token = self.obtain_token(user.username, "p@ssw0rd!123", with_tenant_header=True)
        # Act
        resp = self.client.get(self.url_me, HTTP_AUTHORIZATION=f"Bearer {token}", HTTP_X_TENANT_ID=self.tenant.slug)
        # Assert
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data.get("username"), user.username)
        self.assertIn("tenant_roles", resp.data)
