import { useEffect, useState } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate, Link } from 'react-router-dom';
import { AppBar, Toolbar, IconButton, Typography, Box, Drawer, List, ListItemButton, ListItemIcon, ListItemText, CssBaseline, Container, Divider } from '@mui/material';
import DashboardIcon from '@mui/icons-material/Dashboard';
import PeopleIcon from '@mui/icons-material/People';
import DnsIcon from '@mui/icons-material/Dns';
import MovieFilterIcon from '@mui/icons-material/MovieFilter';
import QueryStatsIcon from '@mui/icons-material/QueryStats';
import LiveTvIcon from '@mui/icons-material/LiveTv';
import SystemUpdateAltIcon from '@mui/icons-material/SystemUpdateAlt';
import Brightness4Icon from '@mui/icons-material/Brightness4';
import Brightness7Icon from '@mui/icons-material/Brightness7';
import LogoutIcon from '@mui/icons-material/Logout';
import Login from './components/Login';
import Dashboard from './components/Dashboard';
import RequireAdmin from './components/RequireAdmin';
import { getAccessToken, isLoggedOut } from './services/api';
import { AppThemeProvider, useThemeMode } from './theme';
import { logout as apiLogout } from './services/auth';
import { useNavigate } from 'react-router-dom';

const drawerWidth = 240;

function Shell({ children }: { children: React.ReactNode }) {
  const { mode, toggle } = useThemeMode();
  const navigate = useNavigate();
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
        <Routes>
          <Route path="/login" element={ isAuthenticated && !isLoggedOut() ? <Navigate to="/dashboard" /> : <Login onLogin={handleLogin} /> } />
          <Route path="/dashboard" element={<RequireAdmin><Shell><Dashboard /></Shell></RequireAdmin>} />
          <Route path="/users" element={<RequireAdmin><Shell><Placeholder title="Users & Sessions" /></Shell></RequireAdmin>} />
          <Route path="/channels" element={<RequireAdmin><Shell><Placeholder title="Channels" /></Shell></RequireAdmin>} />
          <Route path="/live" element={<RequireAdmin><Shell><Placeholder title="Live" /></Shell></RequireAdmin>} />
          <Route path="/shorts/import" element={<RequireAdmin><Shell><Placeholder title="Shorts Import" /></Shell></RequireAdmin>} />
          <Route path="/shorts/metrics" element={<RequireAdmin><Shell><Placeholder title="Shorts Metrics" /></Shell></RequireAdmin>} />
          <Route path="/versions" element={<RequireAdmin><Shell><Placeholder title="App Versions & Features" /></Shell></RequireAdmin>} />
          <Route path="/" element={<Navigate to={isAuthenticated ? '/dashboard' : '/login'} />} />
        </Routes>
      </Router>
    </AppThemeProvider>
  );
}

export default App;
