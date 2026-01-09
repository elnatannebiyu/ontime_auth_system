# Software Requirements Specification (SRS)

## 1. Introduction

### 1.1 Purpose
This document specifies the software requirements for the **Ontime Auth System** (project name in repo: **AuthStack**). The system provides:

- A multi-tenant authentication and authorization backend implemented with **Django + Django REST Framework (DRF)**.
- JWT-based authentication using **SimpleJWT** with **refresh tokens stored in HttpOnly cookies**.
- Role-Based Access Control (RBAC) using Django Groups, including **tenant-scoped roles**.
- Session tracking, device/session management, and session revocation.
- Additional platform modules including channels, shorts ingestion, live streaming endpoints, series content, notifications, and application version gating.

This SRS is intended for:

- Product owners and stakeholders
- Backend and frontend engineers
- QA/test engineers
- DevOps/operations

### 1.2 Scope
The system consists of:

- **Backend API**: `authstack/` Django project providing REST endpoints under `/api/*`.
- **Admin Web Frontend**: `frontend/` React + TypeScript + Material UI application.

The backend also provides module-specific APIs:

- Authentication, roles/permissions, sessions (`accounts`, `user_sessions`)
- OTP-based auth (`otp_auth`)
- Multi-tenancy (`tenants`, `common.tenancy` middleware)
- Channels/playlists/videos/shorts/version features/notifications (`onchannels`)
- Series content (`series`)
- Live/radio streams and tracking (`live`)

### 1.3 Definitions, Acronyms, Abbreviations
- **API**: Application Programming Interface
- **JWT**: JSON Web Token
- **RBAC**: Role-Based Access Control
- **DRF**: Django REST Framework
- **Tenant**: A logical customer/workspace partition in a multi-tenant system
- **Membership**: A user’s association with a tenant and its tenant-scoped roles
- **Access token**: Short-lived JWT used to authorize API calls
- **Refresh token**: Longer-lived JWT used to mint new access tokens
- **JTI**: JWT ID claim used to uniquely identify a token

### 1.4 References
- Backend repo root: `ontime_auth_system/`
- Backend project: `authstack/`
- Frontend project: `frontend/`

Key source-of-truth files (non-exhaustive):

- `authstack/authstack/settings.py`
- `authstack/authstack/urls.py`
- `authstack/accounts/urls.py`
- `authstack/accounts/views.py`
- `authstack/accounts/jwt_auth.py`
- `authstack/common/tenancy.py`
- `authstack/accounts/permissions.py`
- `authstack/accounts/rolemap.py`

### 1.5 Overview
This SRS describes:

- Product perspective and system context
- Actors/roles
- Functional requirements by module
- Data requirements (conceptual model)
- External interface requirements (REST, headers, cookies)
- Non-functional requirements (security, performance, availability)
- Constraints and assumptions

## 2. Overall Description

### 2.1 Product Perspective
The system is a web-based backend service with a separate single-page web frontend.

- The backend authenticates and authorizes requests and exposes REST APIs.
- The frontend authenticates users and consumes backend APIs.

Multi-tenancy is enforced via middleware that resolves the tenant based on:

- `X-Tenant-Id` request header (primary on localhost/mobile clients)
- Subdomain/host-based tenant resolution for deployed portals
- Special query-parameter exceptions for specific preview/proxy endpoints

### 2.2 Product Functions (High-Level)
- User authentication using username/password (optionally disabled) and social login.
- JWT session creation with:
  - refresh token in HttpOnly cookie
  - access token returned to client and stored client-side (frontend uses sessionStorage)
  - refresh token rotation
  - token/session revocation
- Role and permission checks:
  - global roles (Django groups)
  - per-tenant roles via `Membership.roles`
- User self-service:
  - view profile (`/api/me/`)
  - change password / enable/disable password
  - request email verification / verify email
  - password reset request/confirm
  - delete account
- Admin user management:
  - list/update users per tenant
  - manage roles per tenant
  - admin-only endpoints
- Session/device management:
  - list and revoke sessions
  - revoke all sessions
  - admin sessions reporting and revocation
- Additional platform APIs:
  - channels/playlists/videos and shorts ingestion
  - live/radio streaming APIs and tracking
  - series content and tracking
  - notifications and announcements
  - app version checks and feature flags

### 2.3 User Classes and Characteristics
- **Anonymous User**
  - Not authenticated.
  - Can access registration (if enabled), login endpoints, OTP request/verify endpoints, and password reset endpoints.

- **Authenticated User (Tenant Member)**
  - Has valid JWT access token and is a member of the resolved tenant.
  - Can access self-service APIs and permitted resources.

- **Administrator**
  - Has the `Administrator` role (Django group) in the tenant or globally depending on endpoint implementation.
  - Full CRUD across resources (by policy/role mapping).

- **Registrar**
  - Can manage users (add/change) and view other resources.

- **Reviewer/Viewer**
  - Read-only access.

- **Admin Frontend User**
  - Users logging in through the admin frontend must pass an additional constraint:
    - Request includes `X-Admin-Login: 1`
    - User must be in Django group `AdminFrontend`.

### 2.4 Operating Environment
- Backend:
  - Python >= 3.10
  - Django 5.2.5
  - DRF 3.16.1
  - SimpleJWT 5.5.1
  - Deployed behind a reverse proxy (recommended) with proper HTTPS.

- Frontend:
  - React 18
  - TypeScript
  - Vite
  - Material UI

- Data store:
  - Default: SQLite (`authstack/db.sqlite3`)
  - Production recommended: PostgreSQL (dependency included)

- Background jobs:
  - Celery + Redis (configured in settings)

### 2.5 Design and Implementation Constraints
- Multi-tenancy is mandatory for `/api/*` endpoints; missing tenant resolution returns HTTP 400 `{"detail":"Unknown tenant"}`.
- Authentication uses JWT in Authorization header: `Authorization: Bearer <access_token>`.
- Refresh is cookie-based (HttpOnly) and requires `withCredentials: true` on the client.

### 2.6 Assumptions and Dependencies
- Email delivery in production requires SMTP configuration via environment variables.
- Redis is required for Celery operation if background tasks are used.
- Social login requires provider configuration (e.g., Google/Apple credentials).
- Some modules imply media storage (shorts videos) using `MEDIA_ROOT` configured for server paths.

## 3. External Interface Requirements

### 3.1 User Interfaces
- Admin React frontend provides:
  - Login/logout
  - Dashboard
  - Admin user management
  - Admin sessions views
  - Channels/playlists/videos management
  - Shorts ingestion and metrics
  - Series admin
  - Live admin
  - Feature flags and version management
  - Notifications and announcements

### 3.2 Hardware Interfaces
No direct hardware interfaces are required.

### 3.3 Software Interfaces
- **Backend** exposes REST JSON APIs.
- **Frontend** communicates via Axios and expects:
  - access token returned as JSON
  - refresh cookie set by backend
  - 401 handling with refresh retry logic

- **Email service** via SMTP or console backend.
- **Redis** as Celery broker/result backend.

### 3.4 Communications Interfaces
#### 3.4.1 Required Request Headers
- `X-Tenant-Id: <tenant_slug>`
- `Authorization: Bearer <access_token>` for protected endpoints

Optional/auth-related headers:
- `X-Admin-Login: 1` for admin-frontend login flow
- `X-Device-Id`, `X-Device-Name`, `X-Device-Type`, `X-OS-Name`, `X-OS-Version` for session tracking

#### 3.4.2 Cookies
- Refresh token cookie name: defaults to `refresh_token` (configurable in settings).
- Cookie properties:
  - HttpOnly
  - Secure in production
  - SameSite=Lax
  - Path configurable

## 4. System Features and Functional Requirements

> Note: Requirements below are derived from existing implementation and URL mappings. “Shall” statements represent required behavior. Where behavior is inferred or not fully validated in code, it is called out.

### 4.1 Multi-Tenancy
#### 4.1.1 Tenant Resolution
- The system shall resolve the active tenant for each `/api/*` request.
- The system shall resolve tenant using `X-Tenant-Id` when present.
- The system may resolve tenant by host/subdomain or explicit domain mapping (`TenantDomain`).
- If tenant cannot be resolved for an `/api/*` request, the system shall return HTTP 400.

#### 4.1.2 Tenant Access Control
- The system shall deny login if the user is not a `Membership` of the requested tenant.
- The system shall include `tenant_id` in issued access and refresh tokens.
- For protected endpoints requiring tenant validation, the system shall verify that:
  - token claim `tenant_id` matches resolved tenant, and
  - user is a member of the tenant.

### 4.2 Authentication (JWT + Cookies)
#### 4.2.1 Login
Endpoint: `POST /api/token/`
- The system shall authenticate via username/password when enabled by `AUTH_ALLOW_PASSWORD`.
- The system shall enforce brute-force protections:
  - DRF throttle scope `login` (5/min)
  - view-level ip ratelimit (5/min)
  - django-axes middleware
- On success, the system shall return an access token and set a refresh token cookie.
- The system shall create/update a device-based `UserSession` for the user.

#### 4.2.2 Token Refresh
Endpoint: `POST /api/token/refresh/`
- The system shall read the refresh token from HttpOnly cookie.
- If missing, the system shall return HTTP 401 with a “Refresh token not found in cookies” message.
- The system shall rotate refresh tokens on each refresh.
- The system shall update session JTIs and last activity.

#### 4.2.3 Logout
Endpoint: `POST /api/logout/`
- The system shall revoke the current session when possible (via `session_id` claim or cookie JTI fallback).
- The system shall clear the refresh cookie.

### 4.3 User Identity (“Me”) and Account Actions
#### 4.3.1 Get Current User
Endpoint: `GET /api/me/`
- The system shall return user identity fields (username/email/first_name/last_name).
- The system shall return:
  - global roles (groups)
  - tenant roles (Membership.roles for current tenant)
  - effective permissions (merged)
  - `email_verified` flag
  - `has_password` flag

#### 4.3.2 Change Password
Endpoint: `POST /api/me/change-password/`
- The system shall allow authenticated users to change password given current password and new password.
- The system shall validate password strength using configured validators.

#### 4.3.3 Enable/Disable Password
Endpoints:
- `POST /api/me/enable-password/`
- `POST /api/me/disable-password/`
- The system shall allow a user to set or remove password-based login subject to policy (`AUTH_ALLOW_PASSWORD`).

#### 4.3.4 Email Verification
Endpoints:
- `POST /api/me/request-email-verification/`
- `POST /api/me/verify-email/`
- The system shall generate and email a one-time verification token.
- The system shall enforce a per-account cooldown for resending verification emails.
- The system shall mark `UserProfile.email_verified = true` upon successful verification.

#### 4.3.5 Password Reset
Endpoints:
- `POST /api/password-reset/request/`
- `POST /api/password-reset/confirm/`
- The system shall allow an anonymous user to request a password reset.
- The system shall verify a reset token and set a new password.

#### 4.3.6 Account Deletion
Endpoint: `POST /api/me/delete-account/`
- The system shall allow the authenticated user to delete their account subject to confirmation/token rules implemented.

### 4.4 Registration
Endpoint: `POST /api/register/`
- The system shall allow registration with email and password.
- The system shall enforce email domain allowlist if configured.
- The system shall enforce case-insensitive uniqueness across username and email.

### 4.5 Authorization (Roles and Permissions)
#### 4.5.1 RBAC via Roles
- The system shall provide default roles:
  - Administrator
  - Registrar
  - Reviewer
  - Viewer
- The system shall map roles to permissions as defined in `accounts/rolemap.py`.

#### 4.5.2 Permission Checks
- The system shall enforce permissions using DRF permission classes:
  - `HasAnyRole`
  - `DjangoPermissionRequired`
  - `ReadOnlyOrPerm`
  - `IsTenantMember`
  - `TenantMatchesToken`

### 4.6 Admin-Only and Admin User Management
Endpoints (tenant scoped):
- `GET /api/admin-only/`
- `GET /api/admin/users/`
- `GET|PATCH /api/admin/users/<user_id>/`
- `POST|DELETE /api/admin/users/<user_id>/roles/…`

- The system shall restrict admin-only routes to authorized users.
- The system shall allow listing users for a tenant.
- The system shall allow updating user profile fields per policy.
- The system shall allow assigning/removing tenant-scoped roles.

### 4.7 Session Management
Endpoints:
- `GET /api/sessions/`
- `GET /api/sessions/<session_id>/`
- `POST /api/sessions/revoke-all/`
- `GET /api/sessions/admin/stats/`
- `GET /api/sessions/admin/list/`
- `POST /api/sessions/admin/revoke/<session_id>/`

- The system shall record sessions per user and device.
- The system shall support revoking a session and revoking all sessions.
- The system shall update session last activity on token refresh.

### 4.8 OTP Authentication
Base path: `/api/auth/otp/`
Endpoints:
- `POST /api/auth/otp/request/`
- `POST /api/auth/otp/verify/`
- The system shall generate and verify OTP codes according to module implementation.

### 4.9 Device Registration (Refresh Session Service)
Base path: `/api/user-sessions/`
Endpoints:
- `POST /api/user-sessions/register-device/`
- `POST /api/user-sessions/unregister-device/`
- The system shall allow clients to register/unregister devices for push/session use as implemented.

### 4.10 Dynamic Forms
Endpoints:
- `GET /api/forms/schema/`
- `POST /api/forms/validate/`
- `POST /api/forms/submit/`
- `GET /api/forms/config/`
- The system shall expose dynamic form schema and validation services as implemented.

### 4.11 Channels / Media / Shorts / Notifications / Versioning
Base path: `/api/channels/`
Implemented endpoints include:

#### 4.11.1 Versioning and Feature Flags
- `GET /api/channels/version/check/`
- `GET /api/channels/version/latest/`
- `GET /api/channels/version/supported/`
- `GET /api/channels/features/`

The system shall:
- enforce minimum supported versions via middleware (HTTP 426 for outdated builds)
- provide feature flags and version metadata

#### 4.11.2 Channels, Playlists, Videos
- REST endpoints via DRF router for channels (`/api/channels/…`)
- REST endpoints for playlists (`/api/channels/playlists/…`)
- REST endpoints for videos (`/api/channels/videos/…`)

#### 4.11.3 Shorts
- `GET /api/channels/shorts/playlists/`
- `GET /api/channels/shorts/feed/`
- `POST /api/channels/shorts/import/`
- `GET /api/channels/shorts/import/<job_id>/`
- `GET /api/channels/shorts/import/<job_id>/preview/`
- `POST /api/channels/shorts/import/<job_id>/retry/`
- `POST|GET /api/channels/shorts/import/batch/recent/`
- `GET /api/channels/shorts/ready/`
- `GET /api/channels/shorts/ready/feed/`
- Reactions/comments/search endpoints under `/api/channels/shorts/...`
- Admin metrics endpoints under `/api/channels/shorts/admin/metrics/...`

#### 4.11.4 Notifications and Announcements
- `GET /api/channels/notifications/`
- `POST /api/channels/notifications/mark-read/`
- `POST /api/channels/notifications/mark-all-read/`
- `DELETE /api/channels/notifications/<pk>/`
- `GET /api/channels/notifications/unread-count/`
- `GET /api/channels/announcements/first-login/`

### 4.12 Series Module
Base path: `/api/series/`
- Shows, seasons, episodes, categories, reminders: REST endpoints via router.
- Tracking endpoints:
  - `POST /api/series/views/start`
  - `POST /api/series/views/heartbeat`
  - `POST /api/series/views/complete`

### 4.13 Live / Radio Module
Base path: `/api/live/`
- Live and radios: REST endpoints via router.
- Additional endpoints:
  - Radio listing/search/detail
  - Preview endpoints
  - Stream proxy endpoints
  - Listen tracking endpoints (start/heartbeat/stop)

## 5. Data Requirements

### 5.1 Core Entities
- **User** (Django auth User)
  - username (email in many flows)
  - email
  - password (optional for social-only accounts)

- **Tenant**
  - slug
  - name
  - active

- **TenantDomain**
  - tenant_id
  - domain

- **Membership**
  - user_id
  - tenant_id
  - roles (many-to-many to Django Group)

- **UserProfile**
  - user_id
  - email_verified

- **UserSession**
  - id (UUID)
  - user_id
  - device_id/name/type
  - os_name/os_version
  - ip_address
  - user_agent
  - refresh_token_jti / access_token_jti
  - created_at / last_activity / expires_at
  - is_active / revoked_at / revoke_reason

- **ActionToken**
  - purpose (verify email, reset password, etc.)
  - token
  - expires_at
  - used

- **SocialAccount**
  - provider (google/apple)
  - provider_id
  - tokens/metadata

### 5.2 Data Integrity Rules
- Tenant slug shall be unique.
- Membership `(user, tenant)` shall be unique.
- User registration shall enforce case-insensitive uniqueness across username/email.
- Sessions shall have unique refresh token JTI.

## 6. Non-Functional Requirements

### 6.1 Security
- The system shall use HttpOnly cookies for refresh tokens.
- The system shall rotate refresh tokens and revoke old ones.
- The system shall protect login endpoints via throttling and brute-force mitigation.
- The system shall require tenant resolution and tenant membership for protected APIs.
- The system should be deployed with HTTPS and secure cookie flags.

### 6.2 Performance
- Access token validation shall be O(1) per request excluding DB membership checks.
- Token refresh should complete within acceptable latency (<500ms in typical deployments).

### 6.3 Reliability and Availability
- The system shall return clear error messages for missing tenant and missing refresh token.
- Background jobs (Celery) should be optional for core authentication.

### 6.4 Maintainability
- Role definitions shall be centrally maintained in `accounts/rolemap.py`.
- Tenant resolution logic shall be centralized in `common.tenancy.TenantResolverMiddleware`.

### 6.5 Portability
- Backend shall run on Linux/macOS in development.
- Production deployment shall support WSGI (gunicorn) and optionally ASGI.

## 7. Constraints, Risks, and Open Questions

### 7.1 Known Constraints from Implementation
- `/api/*` requires tenant resolution; local usage must send `X-Tenant-Id`.
- Admin frontend login requires membership in `AdminFrontend` group.
- Some modules (live proxy, shorts ingestion) may depend on external networks and media storage.

### 7.2 Open Questions (Need Your Confirmation)
1. What are the official tenants expected in production (how are they created/seeded)?
2. Which user journeys are required for the admin frontend vs mobile app vs public web?
3. Should registration be enabled for all tenants or restricted?
4. What is the intended OTP delivery mechanism (SMS/email) and provider?
5. Social login: which providers must be supported in production and what user linking rules should apply?
6. Which endpoints are intended to be public (AllowAny) besides auth and password reset?
7. What are the SLA/availability targets and expected concurrent users?

## 8. Acceptance Criteria (High-Level)
- Users can log in and receive an access token; refresh cookie is set.
- Authenticated calls succeed with `Authorization: Bearer <token>` and correct tenant.
- Access token expiry triggers refresh flow; refreshed access token works without re-login.
- Logout clears refresh cookie and revokes session.
- Tenant mismatch or missing tenant produces correct error responses.
- Admin users can manage tenant-scoped roles and list sessions.

