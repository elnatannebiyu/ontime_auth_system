import { useEffect, useState } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate, Link } from 'react-router-dom';
import { AppBar, Toolbar, IconButton, Typography, Box, Drawer, List, ListItemButton, ListItemIcon, ListItemText, CssBaseline, Container, Divider, Snackbar, Alert } from '@mui/material';
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
import MyProfile from './components/MyProfile';
import ChannelDetail from './components/ChannelDetail';
import { getAccessToken, isLoggedOut } from './services/api';
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

function Shell({ children }: { children: React.ReactNode }) {
  const { mode, toggle } = useThemeMode();
  const navigate = useNavigate2();
  const handleLogout = async () => {
    try { await apiLogout(); } catch {}
    navigate('/login');
  };
  return (
    <Box sx={{ display: 'flex' }}>
      <CssBaseline />
      <AppBar position="fixed" sx={{ zIndex: (t) => t.zIndex.drawer + 1 }}>
        <Toolbar>
          <Typography variant="h6" sx={{ flexGrow: 1 }}>Ontime Admin</Typography>
          <IconButton color="inherit" onClick={toggle} aria-label="toggle-theme">
            {mode === 'dark' ? <Brightness7Icon /> : <Brightness4Icon />}
          </IconButton>
        </Toolbar>
      </AppBar>
      <Drawer variant="permanent" sx={{ width: drawerWidth, [`& .MuiDrawer-paper`]: { width: drawerWidth, boxSizing: 'border-box', display: 'flex', flexDirection: 'column' } }}>
        <Toolbar />
        <List sx={{ flexGrow: 1 }}>
          <ListItemButton component={Link} to="/dashboard">
            <ListItemIcon><DashboardIcon /></ListItemIcon>
            <ListItemText primary="Dashboard" />
          </ListItemButton>
          <ListItemButton component={Link} to="/users">
            <ListItemIcon><PeopleIcon /></ListItemIcon>
            <ListItemText primary="Users & Sessions" />
          </ListItemButton>
          <ListItemButton component={Link} to="/channels">
            <ListItemIcon><DnsIcon /></ListItemIcon>
            <ListItemText primary="Channels" />
          </ListItemButton>
          <ListItemButton component={Link} to="/playlists">
            <ListItemIcon><MovieFilterIcon /></ListItemIcon>
            <ListItemText primary="Playlists" />
          </ListItemButton>
          <ListItemButton component={Link} to="/videos">
            <ListItemIcon><MovieFilterIcon /></ListItemIcon>
            <ListItemText primary="Videos" />
          </ListItemButton>
          <ListItemButton component={Link} to="/series">
            <ListItemIcon><MovieFilterIcon /></ListItemIcon>
            <ListItemText primary="Series" />
          </ListItemButton>
          <ListItemButton component={Link} to="/live">
            <ListItemIcon><LiveTvIcon /></ListItemIcon>
            <ListItemText primary="Live" />
          </ListItemButton>
          <ListItemButton component={Link} to="/shorts/import">
            <ListItemIcon><MovieFilterIcon /></ListItemIcon>
            <ListItemText primary="Shorts Import" />
          </ListItemButton>
          <ListItemButton component={Link} to="/shorts/metrics">
            <ListItemIcon><QueryStatsIcon /></ListItemIcon>
            <ListItemText primary="Shorts Metrics" />
          </ListItemButton>
          <ListItemButton component={Link} to="/versions">
            <ListItemIcon><SystemUpdateAltIcon /></ListItemIcon>
            <ListItemText primary="App Versions" />
          </ListItemButton>
        </List>
        <Divider />
        <Box sx={{ p: 1 }}>
          <ListItemButton component={Link} to="/profile">
            <ListItemIcon><AccountCircleIcon /></ListItemIcon>
            <ListItemText primary="My Profile" />
          </ListItemButton>
          <ListItemButton onClick={handleLogout}>
            <ListItemIcon><LogoutIcon /></ListItemIcon>
            <ListItemText primary="Logout" />
          </ListItemButton>
        </Box>
      </Drawer>
      <Box component="main" sx={{ flexGrow: 1, p: 3 }}>
        <Toolbar />
        <Container maxWidth="lg">
          {children}
        </Container>
      </Box>
    </Box>
  );
}

function Placeholder({ title }: { title: string }) {
  return <Typography variant="h5" component="h1">{title}</Typography>;
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

  const handleLogin = () => {
    setIsAuthenticated(true);
  };

  return (
    <AppThemeProvider>
      <Router>
        <LogoutWatcher />
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
          <Route path="/shorts/metrics" element={<RequireAdmin><Shell><Placeholder title="Shorts Metrics" /></Shell></RequireAdmin>} />
          <Route path="/versions" element={<RequireAdmin><Shell><AppVersions /></Shell></RequireAdmin>} />
          <Route path="/" element={<Navigate to={isAuthenticated ? '/dashboard' : '/login'} />} />
        </Routes>
      </Router>
    </AppThemeProvider>
  );
}

export default App;
