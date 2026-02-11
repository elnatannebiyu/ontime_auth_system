import React, { useEffect, useRef, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { getCurrentUser, User, refreshToken } from '../services/auth';
import { getAccessToken, isLoggedOut } from '../services/api';
import { Box, CircularProgress } from '@mui/material';

// Module-level guard to avoid multiple redirects in rapid remounts
let redirecting = false;

const RequireAdmin: React.FC<{ children: React.ReactElement }>
  = ({ children }) => {
  const [loading, setLoading] = useState(true);
  const [allowed, setAllowed] = useState(false);
  const [shouldRedirect, setShouldRedirect] = useState(false);
  const triedRefresh = useRef(false);
  const location = useLocation();
  const navigate = useNavigate();
  const redirected = useRef(false);

  useEffect(() => {
    let mounted = true;
    const run = async () => {
      try {
        const hasAccess = !!getAccessToken();
        console.debug('[guard] start', { hasAccess, loggedOut: isLoggedOut() });
        if (!hasAccess) {
          if (isLoggedOut()) {
            console.debug('[guard] no access and loggedOut=true -> redirect');
            if (mounted && !redirecting) {
              redirecting = true;
              setAllowed(false);
              setLoading(false);
              setShouldRedirect(true);
            }
            return;
          }
          if (!triedRefresh.current) {
            triedRefresh.current = true;
            try {
              console.debug('[guard] no access -> try single refresh');
              await refreshToken();
            } catch (e) {
              console.debug('[guard] refresh failed without access');
            }
          }
        }
      } catch {}
      try {
        const me: User = await getCurrentUser();
        // Require AdminFrontend group membership for admin FE
        const roles = me.roles || [];
        const ok = roles.includes('AdminFrontend');
        if (mounted) {
          setAllowed(ok);
          setLoading(false);
          if (!ok && !redirecting) {
            redirecting = true;
            setShouldRedirect(true);
          }
        }
      } catch (e: any) {
        // On 401, try a single refresh, then retry /me
        if (!triedRefresh.current) {
          triedRefresh.current = true;
          try {
            if (isLoggedOut()) {
              console.debug('[guard] loggedOut=true -> skip refresh on 401');
              throw new Error('skip refresh due to loggedOut');
            }
            console.debug('[guard] 401 -> try refresh once');
            await refreshToken();
            const me: User = await getCurrentUser();
            const roles = me.roles || [];
            const ok = roles.includes('AdminFrontend');
            if (mounted) {
              setAllowed(ok);
              setLoading(false);
              if (!ok && !redirecting) {
                redirecting = true;
                setShouldRedirect(true);
              }
            }
            return;
          } catch (_) {
            // fall through to redirect
            console.debug('[guard] refresh failed after 401 -> redirect');
          }
        }
        if (mounted && !redirecting) {
          redirecting = true;
          setAllowed(false);
          setLoading(false);
          setShouldRedirect(true);
        }
      }
    };
    run();
    return () => { mounted = false; redirecting = false; };
  }, []);

  // Perform a single imperative redirect when requested
  useEffect(() => {
    if (shouldRedirect && !redirected.current) {
      redirected.current = true;
      navigate('/login', { replace: true, state: { from: location } });
    }
  }, [shouldRedirect, navigate, location]);

  if (loading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight="100vh">
        <CircularProgress />
      </Box>
    );
  }

  if (!allowed && shouldRedirect) return null;

  return children;
};

export default RequireAdmin;
