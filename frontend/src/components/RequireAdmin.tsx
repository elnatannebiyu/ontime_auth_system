import React, { useEffect, useState } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { getCurrentUser, User } from '../services/auth';
import { Box, CircularProgress } from '@mui/material';

const RequireAdmin: React.FC<{ children: React.ReactElement }>
  = ({ children }) => {
  const [loading, setLoading] = useState(true);
  const [allowed, setAllowed] = useState(false);
  const location = useLocation();

  useEffect(() => {
    let mounted = true;
    const run = async () => {
      try {
        const me: User = await getCurrentUser();
        // Require AdminFrontend group membership for admin FE
        const roles = me.roles || [];
        const ok = roles.includes('AdminFrontend');
        if (mounted) {
          setAllowed(ok);
          setLoading(false);
        }
      } catch (e: any) {
        if (mounted) {
          setAllowed(false);
          setLoading(false);
        }
      }
    };
    run();
    return () => { mounted = false; };
  }, []);

  if (loading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight="100vh">
        <CircularProgress />
      </Box>
    );
  }

  if (!allowed) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  return children;
};

export default RequireAdmin;
