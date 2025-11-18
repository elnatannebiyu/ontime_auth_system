import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Container, Paper, Typography, Box, Grid, Card, CardContent, CircularProgress } from '@mui/material';
import { getCurrentUser, User } from '../services/auth';
import api from '../services/api';

const Dashboard: React.FC = () => {
  const navigate = useNavigate();
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  // Legacy adminMessage/usersData removed; dashboard focuses on KPIs only
  const [redirecting, setRedirecting] = useState(false);

  // KPI states
  const [usersCount, setUsersCount] = useState<number | null>(null);
  const [sessionsCount, setSessionsCount] = useState<number | null>(null);
  const [channelsCount, setChannelsCount] = useState<number | null>(null);
  const [shortsReadyCount, setShortsReadyCount] = useState<number | null>(null);
  const [features, setFeatures] = useState<Record<string, any> | null>(null);
  const [versionInfo, setVersionInfo] = useState<Record<string, any> | null>(null);
  const [shortsTrend, setShortsTrend] = useState<number[]>([]); // last 7 days READY counts
  const [channelsActive, setChannelsActive] = useState<number | null>(null);
  const [channelsInactive, setChannelsInactive] = useState<number | null>(null);
  const [usersTrend, setUsersTrend] = useState<number[]>([]); // last 7 days users
  const [sessionsTrend, setSessionsTrend] = useState<number[]>([]); // last 7 days sessions

  useEffect(() => {
    loadUserData();
  }, []);

  // Load KPIs after we know the user (so we can gate staff-only calls)
  useEffect(() => {
    if (!loading) {
      loadKpis(user);
    }
  }, [loading]);

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
        // Use replace to prevent back button issues
        navigate('/login', { replace: true });
      }
    }
  };

  // Removed legacy admin/test endpoints and users loader

  const loadKpis = async (u: User | null) => {
    try {
      const baseCalls = [
        api.get('/users/'),
        api.get('/sessions/'),
        api.get('/channels/', { params: { page: 1 } }),
      ];
      const allowAdmin = !!(u && (Array.isArray((u as any).roles) && (user as any).roles.includes('AdminFrontend')));
      // Also fetch READY list for a concrete count (cap to 100 for performance)
      const readyCall = allowAdmin
        ? api.get('/channels/shorts/ready/', { params: { limit: 100 } }).catch(() => ({ data: [] }))
        : Promise.resolve({ data: [] } as any);
      // Channels active/inactive counts (fallback filters if needed)
      const chActiveCall = api.get('/channels/', { params: { is_active: true, page: 1 } }).catch(() => ({ data: null }));
      const chInactiveCall = api.get('/channels/', { params: { is_active: false, page: 1 } }).catch(() => ({ data: null }));
      const adminSessionsCall = allowAdmin
        ? api.get('/sessions/admin/stats/').catch(() => ({ data: null }))
        : Promise.resolve({ data: null } as any);

      const [usersRes, sessionsRes, channelsRes, readyRes, chActRes, chInactRes, adminSessRes] = await Promise.all([
        ...baseCalls,
        readyCall,
        chActiveCall,
        chInactiveCall,
        adminSessionsCall,
      ]);
      const uCount = typeof usersRes.data?.count === 'number' ? usersRes.data.count : (Array.isArray(usersRes.data) ? usersRes.data.length : (usersRes.data?.results?.length || 0));
      // Sessions: prefer admin stats when available (active_users)
      let sCount = typeof sessionsRes.data?.count === 'number' ? sessionsRes.data.count : (Array.isArray(sessionsRes.data) ? sessionsRes.data.length : (sessionsRes.data?.results?.length || 0));
      if (adminSessRes.data && typeof adminSessRes.data === 'object' && typeof adminSessRes.data.active_users === 'number') {
        sCount = adminSessRes.data.active_users;
      }
      const cCount = typeof channelsRes.data?.count === 'number' ? channelsRes.data.count : (Array.isArray(channelsRes.data) ? channelsRes.data.length : (channelsRes.data?.results?.length || 0));
      setUsersCount(uCount);
      setSessionsCount(sCount);
      setChannelsCount(cCount);
      // Derive active/inactive from the main channels payload if possible
      try {
        const list = Array.isArray(channelsRes.data) ? channelsRes.data : (channelsRes.data?.results || []);
        const getActive = (it:any) => {
          if (typeof it?.is_active === 'boolean') return it.is_active;
          if (typeof it?.active === 'boolean') return it.active;
          if (typeof it?.enabled === 'boolean') return it.enabled;
          const st = (it?.status || it?.state || '').toString().toLowerCase();
          if (st) return st === 'active' || st === 'enabled';
          return null;
        };
        const tagged = list.map((it:any) => getActive(it)).filter((v:any)=> v !== null);
        if (tagged.length > 0) {
          const a = tagged.filter(Boolean).length;
          const i = tagged.length - a;
          setChannelsActive(a);
          setChannelsInactive(i);
        }
      } catch {}
      // Build 7-day users trend if timestamps available
      try {
        const list = Array.isArray(usersRes.data) ? usersRes.data : (usersRes.data?.results || []);
        const keys = ['created_at','date_joined','joined','createdAt'];
        const today = new Date();
        const buckets = Array.from({ length: 7 }, (_, i) => {
          const d = new Date(today);
          d.setDate(today.getDate() - (6 - i));
          d.setHours(0,0,0,0);
          return d;
        });
        const counts = buckets.map(d => {
          const next = new Date(d); next.setDate(d.getDate() + 1);
          return list.filter((it:any) => {
            const ts = keys.map(k=>it?.[k]).find(Boolean);
            if (!ts) return false;
            const t = new Date(ts);
            return t >= d && t < next;
          }).length;
        });
        setUsersTrend(counts);
      } catch {}
      // Build 7-day sessions trend: prefer admin stats by_day; else fallback to local inference
      try {
        if (adminSessRes.data && Array.isArray(adminSessRes.data.by_day)) {
          const days: Array<{day: string; count: number}> = adminSessRes.data.by_day;
          // Ensure exactly 7 points; fill missing with 0
          const map = new Map(days.map(d => [new Date(d.day).toDateString(), d.count]));
          const today = new Date();
          const counts = Array.from({ length: 7 }, (_, i) => {
            const d = new Date(today);
            d.setDate(today.getDate() - (6 - i));
            return map.get(d.toDateString()) ?? 0;
          });
          setSessionsTrend(counts);
        } else {
          const list = Array.isArray(sessionsRes.data) ? sessionsRes.data : (sessionsRes.data?.results || []);
          const keys = ['last_seen','updated_at','created_at','lastSeen','updatedAt','createdAt'];
          const today = new Date();
          const buckets = Array.from({ length: 7 }, (_, i) => {
            const d = new Date(today);
            d.setDate(today.getDate() - (6 - i));
            d.setHours(0,0,0,0);
            return d;
          });
          const counts = buckets.map(d => {
            const next = new Date(d); next.setDate(d.getDate() + 1);
            return list.filter((it:any) => {
              const ts = keys.map(k=>it?.[k]).find(Boolean);
              if (!ts) return false;
              const t = new Date(ts);
              return t >= d && t < next;
            }).length;
          });
          setSessionsTrend(counts);
          // Log detected timestamp keys across first few items
          try {
            list.slice(0, 5).map((it:any) => ({
              tsKey: keys.find(k => !!it?.[k]) || 'none',
            }));
          } catch {}
        }
      } catch {}
      // Fallback: use filtered calls if derivation above didn't set values
      try {
        const ac = typeof chActRes.data?.count === 'number' ? chActRes.data.count : (Array.isArray(chActRes.data) ? chActRes.data.length : (chActRes.data?.results?.length || 0));
        const ic = typeof chInactRes.data?.count === 'number' ? chInactRes.data.count : (Array.isArray(chInactRes.data) ? chInactRes.data.length : (chInactRes.data?.results?.length || 0));
        let nextA = (channelsActive == null ? ac : channelsActive);
        let nextI = (channelsInactive == null ? ic : channelsInactive);
        // Clamp to total channels count when both available
        if (typeof cCount === 'number' && typeof nextA === 'number' && typeof nextI === 'number') {
          const sum = nextA + nextI;
          if (sum > cCount) {
            // Prefer active from filtered call, derive inactive from total
            const clampedA = Math.min(nextA, cCount);
            const clampedI = Math.max(0, cCount - clampedA);
            nextA = clampedA;
            nextI = clampedI;
          }
        }
        setChannelsActive(nextA);
        setChannelsInactive(nextI);
      } catch {}
      // READY count as primary KPI
      try {
        const rc = Array.isArray(readyRes.data) ? readyRes.data.length : (readyRes.data?.length || 0);
        setShortsReadyCount(rc);
        // Build 7-day trend by updated_at day bucket
        const items: any[] = Array.isArray(readyRes.data) ? readyRes.data : [];
        const today = new Date();
        const buckets = Array.from({ length: 7 }, (_, i) => {
          const d = new Date(today);
          d.setDate(today.getDate() - (6 - i)); // oldest to newest
          d.setHours(0, 0, 0, 0);
          return d;
        });
        const counts = buckets.map((d) => {
          const next = new Date(d); next.setDate(d.getDate() + 1);
          return items.filter((it) => {
            const ts = it.updated_at || it.updatedAt;
            if (!ts) return false;
            const t = new Date(ts);
            return t >= d && t < next;
          }).length;
        });
        setShortsTrend(counts);
      } catch {}

      // Shorts admin metrics dropped from dashboard (show READY count + trend only)

      // Fetch features and version info (non-blocking)
      try {
        const [feat, ver] = await Promise.all([
          api.get('/channels/features/').catch(() => ({ data: null })),
          api.post('/channels/version/check/', { platform: 'web', version: '1.0.0' }).catch(() => ({ data: null })),
        ]);
        if (feat.data && typeof feat.data === 'object') setFeatures(feat.data);
        if (ver.data && typeof ver.data === 'object') setVersionInfo(ver.data);
      } catch {}
    } catch (e: any) {
      // Non-fatal; show partial KPIs
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
            </Box>
          </Paper>
        </Grid>

        {/* KPIs */}
        <Grid item xs={12}>
          <Grid container spacing={3}>
            <Grid item xs={12} md={3}>
              <Card>
                <CardContent>
                  <Typography variant="subtitle2" color="text.secondary">Users</Typography>
                  <Typography variant="h4">{usersCount ?? '—'}</Typography>
                  <Typography variant="body2" color="text.secondary">Total users in this tenant.</Typography>
                  {usersTrend.length === 7 && (
                    <Box sx={{ mt: 1 }}>
                      <svg width="100%" height="40" viewBox="0 0 100 40" preserveAspectRatio="none">
                        {(() => {
                          const max = Math.max(1, ...usersTrend);
                          const pts = usersTrend.map((v, i) => {
                            const x = (i / 6) * 100;
                            const y = 40 - (v / max) * 35 - 2;
                            return `${x},${y}`;
                          }).join(' ');
                          return <polyline fill="none" stroke="currentColor" strokeOpacity="0.7" strokeWidth="2" points={pts} />;
                        })()}
                      </svg>
                    </Box>
                  )}
                </CardContent>
              </Card>
            </Grid>
            <Grid item xs={12} md={3}>
              <Card>
                <CardContent>
                  <Typography variant="subtitle2" color="text.secondary">Sessions</Typography>
                  <Typography variant="h4">{sessionsCount ?? '—'}</Typography>
                  <Typography variant="body2" color="text.secondary">Active sessions currently tracked.</Typography>
                  {sessionsTrend.length === 7 && (
                    <Box sx={{ mt: 1 }}>
                      <svg width="100%" height="40" viewBox="0 0 100 40" preserveAspectRatio="none">
                        {(() => {
                          const max = Math.max(1, ...sessionsTrend);
                          const pts = sessionsTrend.map((v, i) => {
                            const x = (i / 6) * 100;
                            const y = 40 - (v / max) * 35 - 2;
                            return `${x},${y}`;
                          }).join(' ');
                          return <polyline fill="none" stroke="currentColor" strokeOpacity="0.7" strokeWidth="2" points={pts} />;
                        })()}
                      </svg>
                    </Box>
                  )}
                </CardContent>
              </Card>
            </Grid>
            <Grid item xs={12} md={3}>
              <Card>
                <CardContent>
                  <Typography variant="subtitle2" color="text.secondary">Channels</Typography>
                  <Typography variant="h4">{channelsCount ?? '—'}</Typography>
                  <Typography variant="body2" color="text.secondary">Managed channels for this tenant.</Typography>
                  {(typeof channelsActive === 'number' || typeof channelsInactive === 'number') && (
                    <Box sx={{ mt: 1, display: 'flex', alignItems: 'center', gap: 1.5 }}>
                      {(() => {
                        const a = channelsActive ?? 0;
                        const i = channelsInactive ?? 0;
                        const total = Math.max(1, a + i);
                        const aPct = (a / total) * 100;
                        const radius = 16;
                        const circumference = 2 * Math.PI * radius;
                        const aLen = (aPct / 100) * circumference;
                        return (
                          <>
                            <svg width="48" height="48" viewBox="0 0 40 40" aria-hidden>
                              <g transform="rotate(-90 20 20)">
                                <circle cx="20" cy="20" r={radius} fill="none" stroke="#e0e0e0" strokeWidth="8" />
                                <circle
                                  cx="20"
                                  cy="20"
                                  r={radius}
                                  fill="none"
                                  stroke="#2e7d32"
                                  strokeWidth="8"
                                  strokeDasharray={`${aLen} ${circumference - aLen}`}
                                  strokeDashoffset={0}
                                />
                              </g>
                            </svg>
                            <Box sx={{ display: 'flex', flexDirection: 'column' }}>
                              <Typography variant="caption" color="text.secondary">Active: {a}</Typography>
                              <Typography variant="caption" color="text.secondary">Inactive: {i}</Typography>
                            </Box>
                          </>
                        );
                      })()}
                    </Box>
                  )}
                </CardContent>
              </Card>
            </Grid>
            <Grid item xs={12} md={3}>
              <Card>
                <CardContent>
                  <Typography variant="subtitle2" color="text.secondary">Shorts</Typography>
                  <Typography variant="h4">{typeof shortsReadyCount === 'number' ? shortsReadyCount : '—'}</Typography>
                  <Typography variant="body2" color="text.secondary">READY shorts available to play (latest up to 100).</Typography>
                  {shortsTrend.length === 7 && (
                    <Box sx={{ mt: 1 }}>
                      <svg width="100%" height="40" viewBox="0 0 100 40" preserveAspectRatio="none">
                        {(() => {
                          const max = Math.max(1, ...shortsTrend);
                          const pts = shortsTrend.map((v, i) => {
                            const x = (i / 6) * 100;
                            const y = 40 - (v / max) * 35 - 2; // padding
                            return `${x},${y}`;
                          }).join(' ');
                          return <polyline fill="none" stroke="currentColor" strokeOpacity="0.7" strokeWidth="2" points={pts} />;
                        })()}
                      </svg>
                    </Box>
                  )}
                </CardContent>
              </Card>
            </Grid>
          </Grid>
        </Grid>

        {/* Features & Version */}
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>Features</Typography>
              {features ? (
                <Box>
                  {features.platform && (
                    <Typography variant="body2">Platform: {String(features.platform)}</Typography>
                  )}
                  {features.version && (
                    <Typography variant="body2">Version: {String(features.version)}</Typography>
                  )}
                  {features.user_id && (
                    <Typography variant="body2">User ID: {String(features.user_id)}</Typography>
                  )}
                  {features.features && typeof features.features === 'object' && (
                    <Typography variant="body2" color="text.secondary">
                      Features enabled: {Object.keys(features.features).length}
                    </Typography>
                  )}
                  {!features.platform && !features.version && !features.user_id && !features.features && (
                    <Typography variant="body2" color="text.secondary">
                      Features data loaded.
                    </Typography>
                  )}
                </Box>
              ) : (
                <Typography variant="body2" color="text.secondary">No features data.</Typography>
              )}
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>App Version Policy</Typography>
              {versionInfo ? (
                <Box>
                  {versionInfo.platform && <Typography variant="body2">platform: {String(versionInfo.platform)}</Typography>}
                  {versionInfo.version && <Typography variant="body2">version: {String(versionInfo.version)}</Typography>}
                  {versionInfo.build_number && <Typography variant="body2">build: {String(versionInfo.build_number)}</Typography>}
                  {typeof versionInfo.update_required !== 'undefined' && (
                    <Typography variant="body2">update_required: {String(versionInfo.update_required)}</Typography>
                  )}
                  {versionInfo.min_required && <Typography variant="body2">min_required: {String(versionInfo.min_required)}</Typography>}
                  {versionInfo.checked_at && <Typography variant="body2" color="text.secondary">checked_at: {String(versionInfo.checked_at)}</Typography>}
                </Box>
              ) : (
                <Typography variant="body2" color="text.secondary">No version info.</Typography>
              )}
            </CardContent>
          </Card>
        </Grid>

        {/* Legacy user info and protected test sections removed */}
      </Grid>
    </Container>
  );
};

export default Dashboard;
