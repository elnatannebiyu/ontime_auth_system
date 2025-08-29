import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Container,
  Paper,
  Typography,
  Box,
  Button,
  Grid,
  Card,
  CardContent,
  Chip,
  Alert,
  CircularProgress
} from '@mui/material';
import { logout, getCurrentUser, User } from '../services/auth';
import api from '../services/api';

const Dashboard: React.FC = () => {
  const navigate = useNavigate();
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [adminMessage, setAdminMessage] = useState('');
  const [usersData, setUsersData] = useState<any[]>([]);
  const [error, setError] = useState('');
  const [redirecting, setRedirecting] = useState(false);

  useEffect(() => {
    loadUserData();
  }, []);

  const loadUserData = async () => {
    try {
      const userData = await getCurrentUser();
      setUser(userData);
      setLoading(false);
    } catch (err: any) {
      console.error('Failed to load user data:', err);
      setLoading(false);
      
      // Prevent multiple redirect attempts
      if (!redirecting && (err.response?.status === 401 || err.response?.status === 403)) {
        setRedirecting(true);
        setError('Not authenticated. Redirecting to login...');
        // Use replace to prevent back button issues
        navigate('/login', { replace: true });
      }
    }
  };

  const handleLogout = async () => {
    try {
      await logout();
    } catch (err) {
      console.error('Logout error:', err);
    }
    // Clear state and navigate with replace to prevent back button issues
    setUser(null);
    navigate('/login', { replace: true });
  };

  const testAdminEndpoint = async () => {
    try {
      const { data } = await api.get('/admin-only/');
      setAdminMessage(data.msg);
      setError('');
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Not authorized for admin endpoint');
      setAdminMessage('');
    }
  };

  const loadUsers = async () => {
    try {
      const { data } = await api.get('/users/');
      setUsersData(data.results);
      setError('');
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Failed to load users');
    }
  };

  if (loading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight="100vh">
        <CircularProgress />
      </Box>
    );
  }

  return (
    <Container maxWidth="lg" sx={{ mt: 4, mb: 4 }}>
      <Grid container spacing={3}>
        {/* Header */}
        <Grid item xs={12}>
          <Paper sx={{ p: 3 }}>
            <Box display="flex" justifyContent="space-between" alignItems="center">
              <Typography variant="h4">Dashboard</Typography>
              <Button variant="contained" color="secondary" onClick={handleLogout}>
                Logout
              </Button>
            </Box>
          </Paper>
        </Grid>

        {/* User Info */}
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                User Information
              </Typography>
              {user && (
                <>
                  <Typography>Username: {user.username}</Typography>
                  <Typography>Email: {user.email}</Typography>
                  <Typography>Name: {user.first_name} {user.last_name}</Typography>
                  <Box mt={2}>
                    <Typography variant="subtitle2" gutterBottom>Roles:</Typography>
                    {user.roles.map((role) => (
                      <Chip key={role} label={role} size="small" sx={{ mr: 1, mb: 1 }} />
                    ))}
                  </Box>
                  <Box mt={2}>
                    <Typography variant="subtitle2" gutterBottom>Permissions:</Typography>
                    {user.permissions.slice(0, 5).map((perm) => (
                      <Chip 
                        key={perm} 
                        label={perm} 
                        size="small" 
                        variant="outlined" 
                        sx={{ mr: 1, mb: 1 }} 
                      />
                    ))}
                    {user.permissions.length > 5 && (
                      <Typography variant="caption">
                        ... and {user.permissions.length - 5} more
                      </Typography>
                    )}
                  </Box>
                </>
              )}
            </CardContent>
          </Card>
        </Grid>

        {/* Protected Endpoints Test */}
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Test Protected Endpoints
              </Typography>
              
              {error && (
                <Alert severity="error" sx={{ mb: 2 }}>
                  {error}
                </Alert>
              )}
              
              {adminMessage && (
                <Alert severity="success" sx={{ mb: 2 }}>
                  {adminMessage}
                </Alert>
              )}

              <Box display="flex" gap={2} mb={2}>
                <Button 
                  variant="outlined" 
                  onClick={testAdminEndpoint}
                >
                  Test Admin Only
                </Button>
                <Button 
                  variant="outlined" 
                  onClick={loadUsers}
                >
                  Load Users
                </Button>
              </Box>

              {usersData.length > 0 && (
                <Box mt={2}>
                  <Typography variant="subtitle2" gutterBottom>Users:</Typography>
                  <Paper variant="outlined" sx={{ p: 1, maxHeight: 200, overflow: 'auto' }}>
                    {usersData.map((u) => (
                      <Typography key={u.id} variant="body2">
                        {u.username} - {u.email}
                      </Typography>
                    ))}
                  </Paper>
                </Box>
              )}
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Container>
  );
};

export default Dashboard;
