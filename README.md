# AuthStack - Django + React Authentication System

A complete authentication system with Django REST Framework, SimpleJWT, and React. Features include JWT authentication with HttpOnly cookies, role-based access control (RBAC), and automatic token refresh.

## Features

- 🔐 **JWT Authentication** with HttpOnly refresh cookies
- 👥 **Role-Based Access Control** using Django Groups
- 🔑 **Permission System** using Django's built-in permissions
- 🔄 **Automatic Token Refresh** with Axios interceptors
- 🎨 **Modern React UI** with Material-UI
- 🚀 **TypeScript** support in frontend
- 🛡️ **Secure by default** with CORS and CSRF protection

## Project Structure

```
ontime_auth_system/
├── authstack/              # Django backend
│   ├── authstack/          # Django project settings
│   ├── accounts/           # Authentication app
│   │   ├── management/     # Custom management commands
│   │   ├── views.py       # API views
│   │   ├── serializers.py # DRF serializers
│   │   ├── permissions.py # Custom permission classes
│   │   └── rolemap.py    # Role definitions
│   └── requirements.txt   # Python dependencies
├── frontend/              # React frontend
│   ├── src/
│   │   ├── components/    # React components
│   │   ├── services/      # API services
│   │   └── App.tsx       # Main app component
│   ├── public/           # Public assets
│   └── package.json      # Node dependencies
└── README.md             # This file
```

## Quick Start

### Backend Setup

1. **Create virtual environment and install dependencies:**
```bash
cd authstack
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

2. **Run database migrations:**
```bash
python manage.py makemigrations
python manage.py migrate
```

3. **Create a superuser:**
```bash
python manage.py createsuperuser
```

4. **Seed default roles:**
```bash
python manage.py seed_roles
```

5. **Run the Django server:**
```bash
python manage.py runserver
```

The backend will be available at `http://localhost:8000`

### Frontend Setup

1. **Install Node dependencies:**
```bash
cd frontend
npm install
```

2. **Run the development server:**
```bash
npm run dev
```

The frontend will be available at `http://localhost:5173`

## Default Roles

The system comes with three default roles:

- **Administrator**: Full access (all CRUD operations)
- **Registrar**: Can add/change users, view everything
- **Reviewer**: Read-only access to all resources

## API Endpoints

### Authentication
- `POST /api/token/` - Login (returns access token, sets refresh cookie)
- `POST /api/token/refresh/` - Refresh access token (uses HttpOnly cookie)
- `POST /api/logout/` - Logout (clears refresh cookie)

### Protected Endpoints
- `GET /api/me/` - Get current user info (requires authentication)
- `GET /api/admin-only/` - Admin-only endpoint (requires Administrator role)
- `GET /api/users/` - List users (read: any auth user, write: requires permission)

## Testing the System

1. **Access Django Admin:**
   - Navigate to `http://localhost:8000/admin/`
   - Login with superuser credentials
   - Add users to groups (roles)

2. **Test React Frontend:**
   - Navigate to `http://localhost:5173`
   - Login with your credentials
   - Test protected endpoints from the dashboard

## Security Features

- **HttpOnly Cookies**: Refresh tokens stored in HttpOnly cookies (prevents XSS attacks)
- **Token Rotation**: Refresh tokens are rotated on each use
- **Token Blacklist**: Old refresh tokens are blacklisted after rotation
- **CORS Protection**: Configured for specific origins
- **CSRF Protection**: Enabled for cookie-based authentication
- **Secure Flag**: Cookies marked as secure in production (HTTPS only)

## Development vs Production

### Development Settings
- `DEBUG = True`
- Cookies without secure flag
- CORS allowed from localhost

### Production Checklist
- [ ] Set `DEBUG = False`
- [ ] Generate new `SECRET_KEY`
- [ ] Configure proper `ALLOWED_HOSTS`
- [ ] Update `CORS_ALLOWED_ORIGINS`
- [ ] Use HTTPS (cookies will be secure automatically)
- [ ] Configure proper database (PostgreSQL recommended)
- [ ] Set up static files serving
- [ ] Configure email backend for password resets

## Customization

### Adding New Roles

Edit `accounts/rolemap.py`:
```python
ROLE_DEFS = {
    "YourNewRole": {
        "permissions": ["view_*", "add_somemodel"],
    },
}
```

Then run: `python manage.py seed_roles`

### Custom Permissions

Use the provided permission classes in your views:
```python
from accounts.permissions import HasAnyRole, DjangoPermissionRequired

class YourView(APIView):
    permission_classes = [HasAnyRole]
    
    def get_permissions(self):
        p = super().get_permissions()[0]
        p.required_roles = ("Administrator", "YourRole")
        return [p]
```

## Tech Stack

### Backend
- Django 5.1.2
- Django REST Framework 3.15.2
- SimpleJWT 5.4.0
- django-cors-headers 4.4.0

### Frontend
- React 18.2
- TypeScript 5.2
- Material-UI 5.14
- Axios 1.6
- Vite 5.0

## License

MIT License - feel free to use this starter for your projects!

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
