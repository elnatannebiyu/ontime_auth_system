import { useEffect, useState } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { ThemeProvider, createTheme, CssBaseline } from '@mui/material';
import Login from './components/Login';
import Dashboard from './components/Dashboard';
import RequireAdmin from './components/RequireAdmin';
import { getAccessToken, isLoggedOut } from './services/api';

const theme = createTheme({
  palette: {
    mode: 'light',
    primary: {
      main: '#1976d2',
    },
    secondary: {
      main: '#dc004e',
    },
  },
});

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
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <Router>
        <Routes>
          <Route 
            path="/login" 
            element={ isAuthenticated && !isLoggedOut() ? <Navigate to="/dashboard" /> : <Login onLogin={handleLogin} /> } 
          />
          <Route 
            path="/dashboard" 
            element={
              <RequireAdmin>
                <Dashboard />
              </RequireAdmin>
            } 
          />
          <Route 
            path="/" 
            element={<Navigate to={isAuthenticated ? "/dashboard" : "/login"} />} 
          />
        </Routes>
      </Router>
    </ThemeProvider>
  );
}

export default App;
