import { useState } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { ThemeProvider, createTheme, CssBaseline } from '@mui/material';
import Login from './components/Login';
import Dashboard from './components/Dashboard';
import { getAccessToken } from './services/api';

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
  const [isAuthenticated, setIsAuthenticated] = useState(() => {
    // Only check if there's a token already, don't make API calls
    return !!getAccessToken();
  });

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
            element={
              isAuthenticated ? 
                <Navigate to="/dashboard" /> : 
                <Login onLogin={handleLogin} />
            } 
          />
          <Route 
            path="/dashboard" 
            element={<Dashboard />} 
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
