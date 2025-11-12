import React, { useEffect, useMemo, useState } from 'react';
import { Box, Grid, Card, CardContent, CardActions, Typography, TextField, IconButton, Chip, Skeleton, Pagination, Tooltip, Button, Stack } from '@mui/material';
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
      const res = await api.get('/channels/', { params });
      const data = res.data;
      if (Array.isArray(data)) {
        setItems(data as ChannelItem[]);
        setCount(data.length);
      } else {
        setItems((data.results || []) as ChannelItem[]);
        setCount(typeof data.count === 'number' ? data.count : (data.results?.length || 0));
      }
    } catch (e) {
      setItems([]);
      setCount(0);
    } finally {
      setLoading(false);
    }
  };

  const handleSearchKey = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      setPage(1);
      load();
    }
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
          onChange={(e) => setSearch(e.target.value)}
          onKeyDown={handleSearchKey}
        />
        <TextField
          size="small"
          select
          SelectProps={{ native: true }}
          label="Order by"
          value={ordering}
          onChange={(e) => { setOrdering(e.target.value); setPage(1); }}
        >
          <option value="sort_order">Sort order</option>
          <option value="-updated_at">Recently updated</option>
          <option value="id_slug">Slug</option>
        </TextField>
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
                    {isStaff && (
                      <CardActions sx={{ justifyContent: 'space-between' }}>
                        <Stack direction="row" spacing={1}>
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
                        </Stack>
                        <Tooltip title="Open playlists in YouTube (feature coming soon)">
                          <span>
                            <Button size="small" disabled>Playlists</Button>
                          </span>
                        </Tooltip>
                      </CardActions>
                    )}
                  </Card>
                </Grid>
              );
            })}
          </Grid>

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
    </Box>
  );
};

export default Channels;
