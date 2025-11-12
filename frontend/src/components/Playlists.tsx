import React, { useEffect, useMemo, useState } from 'react';
import { Box, Card, CardContent, Chip, Grid, Stack, TextField, Typography, IconButton, Tooltip, Button, FormControl, InputLabel, Select, MenuItem, Pagination, Snackbar, Alert } from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';
import api from '../services/api';
import { getCurrentUser, User } from '../services/auth';

interface PlaylistItem {
  id: string;
  channel: string; // channel slug
  title: string;
  item_count: number;
  is_active: boolean;
  channel_logo_url?: string;
  thumbnail_url?: string | null;
}

const pageSize = 24;

const Playlists: React.FC = () => {
  const [items, setItems] = useState<PlaylistItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [channel, setChannel] = useState('');
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState<'all'|'active'|'inactive'>('all');
  const [ordering, setOrdering] = useState<string>('title');
  const [page, setPage] = useState(1);
  const [count, setCount] = useState(0);
  const [err, setErr] = useState<string | null>(null);
  const [busyIds, setBusyIds] = useState<Set<string>>(new Set());
  const [user, setUser] = useState<User | null>(null);
  const isStaff = useMemo(() => !!(user && ((user as any).is_staff || (Array.isArray((user as any).roles) && (user as any).roles.includes('AdminFrontend')))), [user]);

  useEffect(()=>{ (async()=>{ try { setUser(await getCurrentUser()); } catch {} })(); }, []);

  const load = async () => {
    setLoading(true);
    try {
      const params: any = { page, ordering };
      if (channel.trim()) params.channel = channel.trim();
      if (search.trim()) params.search = search.trim();
      if (status !== 'all') params.is_active = (status === 'active');
      const { data } = await api.get('/channels/playlists/', { params });
      const list = Array.isArray(data) ? data : (data?.results || []);
      setItems(list);
      setCount(typeof data?.count === 'number' ? data.count : list.length);
    } catch (e:any) {
      setItems([]); setCount(0);
      setErr(e?.response?.data?.detail || 'Failed to load playlists');
    } finally {
      setLoading(false);
    }
  };

  useEffect(()=>{ load(); }, [page, ordering, status]);

  const onToggle = async (pl: PlaylistItem, next: boolean) => {
    const key = `${pl.id}-${next?'act':'deact'}`;
    setBusyIds(prev => new Set(prev).add(key));
    try {
      await api.post(`/playlists/${encodeURIComponent(pl.id)}/${next? 'activate':'deactivate'}/`);
      await load();
    } catch (e:any) {
      setErr(e?.response?.data?.detail || 'Failed to update playlist');
    } finally {
      setBusyIds(prev => { const n = new Set(prev); n.delete(key); return n; });
    }
  };

  return (
    <Stack spacing={2}>
      <Stack direction="row" spacing={2} alignItems="center" sx={{ flexWrap:'wrap' }}>
        <Typography variant="h5" sx={{ flexGrow: 1 }}>Playlists</Typography>
        <TextField size="small" label="Search title" value={search} onChange={(e)=>{ setSearch(e.target.value); setPage(1); }} onKeyDown={(e)=>{ if (e.key==='Enter') load(); }} />
        <TextField size="small" label="Channel slug" value={channel} onChange={e=>setChannel(e.target.value)} onKeyDown={(e)=>{ if (e.key==='Enter') { setPage(1); load(); } }} />
        <FormControl size="small">
          <InputLabel id="status-label">Status</InputLabel>
          <Select labelId="status-label" label="Status" value={status} onChange={(e)=>{ setStatus(e.target.value as any); setPage(1); }}>
            <MenuItem value="all">All</MenuItem>
            <MenuItem value="active">Active</MenuItem>
            <MenuItem value="inactive">Inactive</MenuItem>
          </Select>
        </FormControl>
        <FormControl size="small">
          <InputLabel id="order-label">Order by</InputLabel>
          <Select labelId="order-label" label="Order by" value={ordering} onChange={(e)=>{ setOrdering(e.target.value as string); setPage(1); }}>
            <MenuItem value="title">Title</MenuItem>
            <MenuItem value="-updated_at">Recently updated</MenuItem>
            <MenuItem value="item_count">Item count</MenuItem>
          </Select>
        </FormControl>
        <Tooltip title="Reload"><span><IconButton onClick={load} disabled={loading}><RefreshIcon/></IconButton></span></Tooltip>
      </Stack>

      <Grid container spacing={2}>
        {items.map(pl => (
          <Grid item xs={12} sm={6} md={4} lg={3} key={pl.id}>
            <Card>
              <Box sx={{ height: 140, display: 'flex', alignItems:'center', justifyContent:'center', bgcolor:'action.hover' }}>
                {/* eslint-disable-next-line jsx-a11y/img-redundant-alt */}
                {pl.thumbnail_url ? (
                  <img src={pl.thumbnail_url} alt={`Thumbnail`} style={{ maxHeight: 120, maxWidth:'90%', objectFit:'cover' }} />
                ) : (
                  <img src={pl.channel_logo_url || ''} alt={`Channel logo`} style={{ maxHeight: 120, maxWidth:'90%', objectFit:'contain' }} />
                )}
              </Box>
              <CardContent>
                <Box sx={{ display:'flex', justifyContent:'space-between', alignItems:'center', gap:1 }}>
                  <Typography variant="subtitle1" noWrap title={pl.title}>{pl.title}</Typography>
                  <Chip size="small" label={`${pl.item_count}`} />
                </Box>
                <Typography variant="caption" color="text.secondary">{pl.channel}</Typography>
                <Box sx={{ mt: 1, display:'flex', alignItems:'center', justifyContent:'space-between' }}>
                  <Chip size="small" color={pl.is_active ? 'success' : 'default'} label={pl.is_active ? 'Active' : 'Inactive'} />
                  {isStaff && (
                    <span>
                      <Button size="small" variant={pl.is_active? 'outlined':'contained'} color={pl.is_active? 'warning':'primary'} disabled={busyIds.has(`${pl.id}-${pl.is_active?'deact':'act'}`)} onClick={()=>onToggle(pl, !pl.is_active)}>
                        {pl.is_active? 'Deactivate':'Activate'}
                      </Button>
                    </span>
                  )}
                </Box>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>

      <Box sx={{ display:'flex', justifyContent:'center', my:2 }}>
        <Pagination page={page} onChange={(_,p)=>setPage(p)} count={Math.max(1, Math.ceil(count / pageSize))} color="primary" />
      </Box>

      <Snackbar open={!!err} autoHideDuration={4000} onClose={()=>setErr(null)}>
        <Alert severity="error" variant="filled" onClose={()=>setErr(null)} sx={{ width:'100%' }}>{err}</Alert>
      </Snackbar>
    </Stack>
  );
};

export default Playlists;
