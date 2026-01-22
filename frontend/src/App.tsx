import { useEffect, useState } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate, Link } from 'react-router-dom';
import { AppBar, Toolbar, IconButton, Typography, Box, Drawer, List, ListItemButton, ListItemIcon, ListItemText, CssBaseline, Container, Divider, Snackbar, Alert, useTheme, useMediaQuery } from '@mui/material';
import DashboardIcon from '@mui/icons-material/Dashboard';
import PeopleIcon from '@mui/icons-material/People';
import DnsIcon from '@mui/icons-material/Dns';
import MovieFilterIcon from '@mui/icons-material/MovieFilter';
import QueryStatsIcon from '@mui/icons-material/QueryStats';
import LiveTvIcon from '@mui/icons-material/LiveTv';
import SystemUpdateAltIcon from '@mui/icons-material/SystemUpdateAlt';
import AccountCircleIcon from '@mui/icons-material/AccountCircle';
import Brightness4Icon from '@mui/icons-material/Brightness4';
import Brightness7Icon from '@mui/icons-material/Brightness7';
import LogoutIcon from '@mui/icons-material/Logout';
import MenuIcon from '@mui/icons-material/Menu';
import Login from './components/Login';
import Dashboard from './components/Dashboard';
import AdminUsers from './components/AdminUsers';
import AdminSessions from './components/AdminSessions';
import RequireAdmin from './components/RequireAdmin';
import Channels from './components/Channels';
import AppVersions from './components/AppVersions';
import Playlists from './components/Playlists';
import Videos from './components/Videos';
import ShortsIngestion from './components/ShortsIngestion';
import ShortsMetrics from './components/ShortsMetrics';
import MyProfile from './components/MyProfile';
import ChannelDetail from './components/ChannelDetail';
import { getAccessToken, isLoggedOut, bootstrapAuth } from './services/api';
import LiveAdmin from './components/LiveAdmin';
import SeriesAdmin from './components/SeriesAdmin';
import { AppThemeProvider, useThemeMode } from './theme';
import { logout as apiLogout } from './services/auth';
import { useNavigate as useNavigate2 } from 'react-router-dom';

const drawerWidth = 240;

function LogoutWatcher() {
  const [open, setOpen] = useState(false);
  const navigate = useNavigate2();
  useEffect(() => {
    const onLogout = () => {
      setOpen(true);
      // Redirect immediately; toast will still show on the login page mount for a moment
      navigate('/login', { replace: true });
    };
    window.addEventListener('admin_fe_logout', onLogout);
    return () => window.removeEventListener('admin_fe_logout', onLogout);
  }, [navigate]);
  return (
    <Snackbar open={open} autoHideDuration={3000} onClose={() => setOpen(false)} anchorOrigin={{ vertical: 'top', horizontal: 'center' }}>
      <Alert severity="warning" variant="filled" onClose={() => setOpen(false)} sx={{ width: '100%' }}>
        Session expired, please log in again
      </Alert>
    </Snackbar>
  );
}

const INACTIVITY_LIMIT_MS = 15 * 60 * 1000;
const LAST_ACTIVE_KEY = 'admin_fe_lastActive';

function InactivityWatcher() {
  useEffect(() => {
    const updateLastActive = () => {
      if (!getAccessToken() || isLoggedOut()) return;
      try {
        localStorage.setItem(LAST_ACTIVE_KEY, String(Date.now()));
      } catch {}
    };

    const events: (keyof WindowEventMap)[] = ['click', 'keydown', 'mousemove', 'scroll', 'focus'];
    events.forEach((evt) => window.addEventListener(evt, updateLastActive));

    const onStorage = (e: StorageEvent) => {
      if (e.key === LAST_ACTIVE_KEY && e.newValue) {
        // No local state to update; presence of this handler keeps effect subscribed
      }
    };
    window.addEventListener('storage', onStorage);

    updateLastActive();

    const id = window.setInterval(async () => {
      if (!getAccessToken() || isLoggedOut()) return;
      let last = 0;
      try {
        const raw = localStorage.getItem(LAST_ACTIVE_KEY);
        if (raw) last = Number(raw) || 0;
      } catch {}
      if (!last) {
        try { localStorage.setItem(LAST_ACTIVE_KEY, String(Date.now())); } catch {}
        return;
      }
      const inactiveFor = Date.now() - last;
      if (inactiveFor >= INACTIVITY_LIMIT_MS) {
        try {
          await apiLogout();
        } catch {}
      }
    }, 30000);

    return () => {
      events.forEach((evt) => window.removeEventListener(evt, updateLastActive));
      window.removeEventListener('storage', onStorage);
      window.clearInterval(id);
    };
  }, []);

  return null;
}

function Shell({ children }: { children: React.ReactNode }) {
  const { mode, toggle } = useThemeMode();
  const navigate = useNavigate2();
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down('md'));
  const [mobileOpen, setMobileOpen] = useState(false);
  const handleDrawerToggle = () => {
    setMobileOpen((prev) => !prev);
  };
  const handleLogout = async () => {
    try { await apiLogout(); } catch {}
    navigate('/login');
  };
  const drawerContent = (
    <>
      <Toolbar />
      <List sx={{ flexGrow: 1 }}>
        <ListItemButton component={Link} to="/dashboard" onClick={() => isMobile && setMobileOpen(false)}>
          <ListItemIcon><DashboardIcon /></ListItemIcon>
          <ListItemText primary="Dashboard" />
        </ListItemButton>
        <ListItemButton component={Link} to="/users" onClick={() => isMobile && setMobileOpen(false)}>
          <ListItemIcon><PeopleIcon /></ListItemIcon>
          <ListItemText primary="Users & Sessions" />
        </ListItemButton>
        <ListItemButton component={Link} to="/channels" onClick={() => isMobile && setMobileOpen(false)}>
          <ListItemIcon><DnsIcon /></ListItemIcon>
          <ListItemText primary="Channels" />
        </ListItemButton>
        <ListItemButton component={Link} to="/playlists" onClick={() => isMobile && setMobileOpen(false)}>
          <ListItemIcon><MovieFilterIcon /></ListItemIcon>
          <ListItemText primary="Playlists" />
        </ListItemButton>
        <ListItemButton component={Link} to="/videos" onClick={() => isMobile && setMobileOpen(false)}>
          <ListItemIcon><MovieFilterIcon /></ListItemIcon>
          <ListItemText primary="Videos" />
        </ListItemButton>
        <ListItemButton component={Link} to="/series" onClick={() => isMobile && setMobileOpen(false)}>
          <ListItemIcon><MovieFilterIcon /></ListItemIcon>
          <ListItemText primary="Series" />
        </ListItemButton>
        <ListItemButton component={Link} to="/live" onClick={() => isMobile && setMobileOpen(false)}>
          <ListItemIcon><LiveTvIcon /></ListItemIcon>
          <ListItemText primary="Live" />
        </ListItemButton>
        <ListItemButton component={Link} to="/shorts/import" onClick={() => isMobile && setMobileOpen(false)}>
          <ListItemIcon><MovieFilterIcon /></ListItemIcon>
          <ListItemText primary="Shorts Import" />
        </ListItemButton>
        <ListItemButton component={Link} to="/shorts/metrics" onClick={() => isMobile && setMobileOpen(false)}>
          <ListItemIcon><QueryStatsIcon /></ListItemIcon>
          <ListItemText primary="Shorts Metrics" />
        </ListItemButton>
        <ListItemButton component={Link} to="/versions" onClick={() => isMobile && setMobileOpen(false)}>
          <ListItemIcon><SystemUpdateAltIcon /></ListItemIcon>
          <ListItemText primary="App Versions" />
        </ListItemButton>
      </List>
      <Divider />
      <Box sx={{ p: 1 }}>
        <ListItemButton component={Link} to="/profile" onClick={() => isMobile && setMobileOpen(false)}>
          <ListItemIcon><AccountCircleIcon /></ListItemIcon>
          <ListItemText primary="My Profile" />
        </ListItemButton>
        <ListItemButton onClick={handleLogout}>
          <ListItemIcon><LogoutIcon /></ListItemIcon>
          <ListItemText primary="Logout" />
        </ListItemButton>
      </Box>
    </>
  );
  return (
    <Box sx={{ display: 'flex', minHeight: '100vh' }}>
      <CssBaseline />
      <AppBar position="fixed" sx={{ zIndex: (t) => t.zIndex.drawer + 1 }}>
        <Toolbar>
          {isMobile && (
            <IconButton
              color="inherit"
              edge="start"
              onClick={handleDrawerToggle}
              sx={{ mr: 2 }}
              aria-label="open navigation menu"
            >
              <MenuIcon />
            </IconButton>
          )}
          <Typography variant="h6" sx={{ flexGrow: 1 }}>Ontime Admin</Typography>
          <IconButton color="inherit" onClick={toggle} aria-label="toggle-theme">
            {mode === 'dark' ? <Brightness7Icon /> : <Brightness4Icon />}
          </IconButton>
        </Toolbar>
      </AppBar>
      <Box component="nav" sx={{ flexShrink: { sm: 0 } }} aria-label="admin navigation">
        <Drawer
          variant="temporary"
          open={mobileOpen}
          onClose={handleDrawerToggle}
          ModalProps={{ keepMounted: true }}
          sx={{
            display: { xs: 'block', md: 'none' },
            [`& .MuiDrawer-paper`]: { width: drawerWidth, boxSizing: 'border-box' },
          }}
        >
          {drawerContent}
        </Drawer>
        <Drawer
          variant="permanent"
          sx={{
            display: { xs: 'none', md: 'flex' },
            width: drawerWidth,
            [`& .MuiDrawer-paper`]: { width: drawerWidth, boxSizing: 'border-box', display: 'flex', flexDirection: 'column' },
          }}
          open
        >
          {drawerContent}
        </Drawer>
      </Box>
      <Box component="main" sx={{ flexGrow: 1, p: { xs: 2, md: 3 }, width: '100%' }}>
        <Toolbar />
        <Container maxWidth="lg">
          {children}
        </Container>
      </Box>
    </Box>
  );
}

function App() {
  // Don't check authentication on initial load to prevent loops
  // Let the protected routes handle their own authentication
  const [isAuthenticated, setIsAuthenticated] = useState(() => !!getAccessToken() && !isLoggedOut());

  useEffect(() => {
    const onLogout = () => setIsAuthenticated(false);
    window.addEventListener('admin_fe_logout', onLogout);
    return () => window.removeEventListener('admin_fe_logout', onLogout);
  }, []);

  // Align FE-BE flow on cold loads: try to obtain access via refresh cookie silently
  useEffect(() => {
    (async () => {
      try {
        const ok = await bootstrapAuth();
        if (ok) setIsAuthenticated(true);
      } catch {}
    })();
  }, []);

  const handleLogin = () => {
    setIsAuthenticated(true);
  };

  return (
    <AppThemeProvider>
      <Router>
        <LogoutWatcher />
        <InactivityWatcher />
        <Routes>
          <Route path="/login" element={ isAuthenticated && !isLoggedOut() ? <Navigate to="/dashboard" /> : <Login onLogin={handleLogin} /> } />
          <Route path="/dashboard" element={<RequireAdmin><Shell><Dashboard /></Shell></RequireAdmin>} />
          <Route path="/users" element={<RequireAdmin><Shell><AdminUsers /></Shell></RequireAdmin>} />
          <Route path="/channels" element={<RequireAdmin><Shell><Channels /></Shell></RequireAdmin>} />
          <Route path="/channels/:slug" element={<RequireAdmin><Shell><ChannelDetail /></Shell></RequireAdmin>} />
          <Route path="/playlists" element={<RequireAdmin><Shell><Playlists /></Shell></RequireAdmin>} />
          <Route path="/videos" element={<RequireAdmin><Shell><Videos /></Shell></RequireAdmin>} />
          <Route path="/users/sessions" element={<RequireAdmin><Shell><AdminSessions /></Shell></RequireAdmin>} />
          <Route path="/profile" element={<RequireAdmin><Shell><MyProfile /></Shell></RequireAdmin>} />
          <Route path="/live" element={<RequireAdmin><Shell><LiveAdmin /></Shell></RequireAdmin>} />
          <Route path="/series" element={<RequireAdmin><Shell><SeriesAdmin /></Shell></RequireAdmin>} />
          <Route path="/shorts/import" element={<RequireAdmin><Shell><ShortsIngestion /></Shell></RequireAdmin>} />
          <Route path="/shorts/metrics" element={<RequireAdmin><Shell><ShortsMetrics /></Shell></RequireAdmin>} />
          <Route path="/versions" element={<RequireAdmin><Shell><AppVersions /></Shell></RequireAdmin>} />
          <Route path="/" element={<Navigate to={isAuthenticated ? '/dashboard' : '/login'} />} />
        </Routes>
      </Router>
    </AppThemeProvider>
  );
}

export default App;
