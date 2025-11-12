import React, { useEffect, useMemo, useState } from 'react';
import { Box, Grid, Card, CardContent, CardActions, Typography, TextField, IconButton, Chip, Skeleton, Pagination, Tooltip, Button, Stack, MenuItem, Select, FormControl, InputLabel, Snackbar, Alert } from '@mui/material';
import { Link as RouterLink } from 'react-router-dom';
import SyncIcon from '@mui/icons-material/Sync';
import PlaylistAddIcon from '@mui/icons-material/PlaylistAdd';
import RefreshIcon from '@mui/icons-material/Refresh';
import ToggleOnIcon from '@mui/icons-material/ToggleOn';
import ToggleOffIcon from '@mui/icons-material/ToggleOff';
import api from '../services/api';
import { getCurrentUser, User } from '../services/auth';

interface ChannelItem {
  uid: string;
  id_slug: string;
  name_en?: string | null;
  name_am?: string | null;
  is_active: boolean;
  logo_url?: string;
  updated_at?: string;
  sort_order?: number;
}

const pageSize = 24;

const Channels: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [user, setUser] = useState<User | null>(null);
  const [items, setItems] = useState<ChannelItem[]>([]);
  const [count, setCount] = useState<number>(0);
  const [page, setPage] = useState<number>(1);
  const [search, setSearch] = useState<string>('');
  const [ordering, setOrdering] = useState<string>('sort_order');
  const [busyIds, setBusyIds] = useState<Set<string>>(new Set());
  const [status, setStatus] = useState<'all'|'active'|'inactive'>('all');
  const [error, setError] = useState<string | null>(null);
  const [searchTimer, setSearchTimer] = useState<any>(null);

  const isStaff = useMemo(() => !!(user && ((user as any).is_staff || (Array.isArray((user as any).roles) && (user as any).roles.includes('AdminFrontend')))), [user]);

  useEffect(() => {
    (async () => {
      try { setUser(await getCurrentUser()); } catch {}
      await load();
    })();
  }, []);

  useEffect(() => {
    // reload when filters/page change
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, ordering]);

  const load = async () => {
    setLoading(true);
    try {
      const params: any = { page, ordering };
      if (search.trim()) params.search = search.trim();
      if (status !== 'all') params.is_active = (status === 'active');
      const res = await api.get('/channels/', { params });
      const data = res.data;
      if (Array.isArray(data)) {
        setItems(data as ChannelItem[]);
        setCount(data.length);
      } else {
        setItems((data.results || []) as ChannelItem[]);
        setCount(typeof data.count === 'number' ? data.count : (data.results?.length || 0));
      }
    } catch (e: any) {
      setItems([]);
      setCount(0);
      setError(e?.response?.data?.detail || 'Failed to load channels');
    } finally {
      setLoading(false);
    }
  };

  const syncPlaylists = async (slug: string) => {
    if (!isStaff) return; setBusyIds(prev => new Set(prev).add(`sync-pl-${slug}`));
    try { await api.post(`/channels/${encodeURIComponent(slug)}/yt/sync-playlists/`); await load(); } catch {} finally {
      setBusyIds(prev => { const n = new Set(prev); n.delete(`sync-pl-${slug}`); return n; });
    }
  };

  const syncAll = async (slug: string) => {
    if (!isStaff) return; setBusyIds(prev => new Set(prev).add(`sync-all-${slug}`));
    try { await api.post(`/channels/${encodeURIComponent(slug)}/yt/sync-all/`); await load(); } catch {} finally {
      setBusyIds(prev => { const n = new Set(prev); n.delete(`sync-all-${slug}`); return n; });
    }
  };

  const handleSearchChange = (v: string) => {
    setSearch(v);
    if (searchTimer) clearTimeout(searchTimer);
    const t = setTimeout(() => { setPage(1); load(); }, 400);
    setSearchTimer(t);
  };

  const toggleActive = async (ch: ChannelItem, nextActive: boolean) => {
    if (!isStaff) return;
    const slug = ch.id_slug;
    const id = slug;
    setBusyIds(prev => new Set(prev).add(id));
    try {
      await api.post(`/channels/${encodeURIComponent(slug)}/${nextActive ? 'activate' : 'deactivate'}/`);
      // optimistic update
      setItems(prev => prev.map(it => (it.id_slug === slug ? { ...it, is_active: nextActive } : it)));
    } catch (e) {
      // ignore; UI will remain unchanged on failure
    } finally {
      setBusyIds(prev => { const n = new Set(prev); n.delete(id); return n; });
    }
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, mb: 2, flexWrap: 'wrap' }}>
        <Typography variant="h5" component="h1" sx={{ flexGrow: 1 }}>Channels</Typography>
        <TextField
          size="small"
          label="Search"
          placeholder="Search by name or slug"
          value={search}
          onChange={(e) => handleSearchChange(e.target.value)}
        />
        <FormControl size="small">
          <InputLabel id="order-label">Order by</InputLabel>
          <Select labelId="order-label" label="Order by" value={ordering} onChange={(e)=>{ setOrdering(e.target.value as string); setPage(1); load(); }}>
            <MenuItem value="sort_order">Sort order</MenuItem>
            <MenuItem value="-updated_at">Recently updated</MenuItem>
            <MenuItem value="id_slug">Slug</MenuItem>
          </Select>
        </FormControl>
        <FormControl size="small">
          <InputLabel id="status-label">Status</InputLabel>
          <Select labelId="status-label" label="Status" value={status} onChange={(e)=>{ setStatus(e.target.value as any); setPage(1); load(); }}>
            <MenuItem value="all">All</MenuItem>
            <MenuItem value="active">Active</MenuItem>
            <MenuItem value="inactive">Inactive</MenuItem>
          </Select>
        </FormControl>
        <Tooltip title="Reload">
          <span>
            <IconButton onClick={load} aria-label="reload" disabled={loading}>
              <RefreshIcon />
            </IconButton>
          </span>
        </Tooltip>
      </Box>

      {loading ? (
        <Grid container spacing={2}>
          {Array.from({ length: 12 }).map((_, i) => (
            <Grid key={i} item xs={12} sm={6} md={4} lg={3}>
              <Card>
                <Skeleton variant="rectangular" height={140} />
                <CardContent>
                  <Skeleton variant="text" width="60%" />
                  <Skeleton variant="text" width="40%" />
                </CardContent>
              </Card>
            </Grid>
          ))}
        </Grid>
      ) : (
        <>
          {items.length === 0 ? (
            <Box sx={{ py: 8, textAlign: 'center', width: '100%' }}>
              <Typography variant="body1" color="text.secondary">No channels found.</Typography>
            </Box>
          ) : (
            <Grid container spacing={2}>
            {items.map((ch) => {
              const title = ch.name_en || ch.name_am || ch.id_slug;
              const logo = ch.logo_url || `/api/channels/${encodeURIComponent(ch.id_slug)}/logo/`;
              const busy = busyIds.has(ch.id_slug);
              return (
                <Grid key={ch.uid || ch.id_slug} item xs={12} sm={6} md={4} lg={3}>
                  <Card>
                    <Box sx={{ height: 140, display: 'flex', alignItems: 'center', justifyContent: 'center', bgcolor: 'action.hover' }}>
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={logo} alt={`${title} logo`} style={{ maxHeight: 120, maxWidth: '90%', objectFit: 'contain' }} onError={(e:any)=>{ e.currentTarget.style.visibility='hidden'; }} />
                    </Box>
                    <CardContent>
                      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 1 }}>
                        <Typography variant="subtitle1" noWrap title={title}>{title}</Typography>
                        <Chip size="small" color={ch.is_active ? 'success' : 'default'} label={ch.is_active ? 'Active' : 'Inactive'} />
                      </Box>
                      <Typography variant="caption" color="text.secondary">{ch.id_slug}</Typography>
                    </CardContent>
                    <CardActions sx={{ justifyContent: 'space-between', flexWrap: 'wrap' }}>
                      <Stack direction="row" spacing={1}>
                        <Button component={RouterLink} to={`/channels/${encodeURIComponent(ch.id_slug)}`} size="small">Details</Button>
                        {isStaff && (
                          <Tooltip title={ch.is_active ? 'Deactivate' : 'Activate'}>
                            <span>
                              <Button
                                size="small"
                                variant="outlined"
                                color={ch.is_active ? 'warning' : 'primary'}
                                startIcon={ch.is_active ? <ToggleOffIcon /> : <ToggleOnIcon />}
                                disabled={busy}
                                onClick={() => toggleActive(ch, !ch.is_active)}
                              >
                                {ch.is_active ? 'Deactivate' : 'Activate'}
                              </Button>
                            </span>
                          </Tooltip>
                        )}
                      </Stack>
                      {isStaff && (
                        <Stack direction="row" spacing={1}>
                          <Tooltip title="Sync playlists">
                            <span>
                              <Button size="small" variant="outlined" startIcon={<PlaylistAddIcon/>} disabled={busyIds.has(`sync-pl-${ch.id_slug}`)} onClick={()=>syncPlaylists(ch.id_slug)}>Sync PL</Button>
                            </span>
                          </Tooltip>
                          <Tooltip title="Sync all (playlists + videos)">
                            <span>
                              <Button size="small" variant="contained" startIcon={<SyncIcon/>} disabled={busyIds.has(`sync-all-${ch.id_slug}`)} onClick={()=>syncAll(ch.id_slug)}>Sync All</Button>
                            </span>
                          </Tooltip>
                        </Stack>
                      )}
                    </CardActions>
                  </Card>
                </Grid>
              );
            })}
            </Grid>
          )}

          <Box sx={{ display: 'flex', justifyContent: 'center', my: 3 }}>
            <Pagination
              page={page}
              onChange={(_, p) => setPage(p)}
              color="primary"
              count={Math.max(1, Math.ceil(count / pageSize))}
            />
          </Box>
        </>
      )}

      <Snackbar open={!!error} autoHideDuration={4000} onClose={()=>setError(null)}>
        <Alert onClose={()=>setError(null)} severity="error" variant="filled" sx={{ width: '100%' }}>
          {error}
        </Alert>
      </Snackbar>
    </Box>
  );
};

export default Channels;
