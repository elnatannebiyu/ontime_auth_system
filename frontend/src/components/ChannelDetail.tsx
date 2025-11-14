import React, { useEffect, useMemo, useState } from 'react';
import { useParams } from 'react-router-dom';
import { Box, Button, Card, CardContent, Chip, Grid, Stack, Tab, Tabs, Typography, IconButton, Tooltip, TextField, Pagination, Snackbar, Alert } from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';
import SyncIcon from '@mui/icons-material/Sync';
import PlaylistAddIcon from '@mui/icons-material/PlaylistAdd';
import api from '../services/api';
import { getCurrentUser, User } from '../services/auth';

const ChannelDetail: React.FC = () => {
  const { slug } = useParams();
  const [user, setUser] = useState<User | null>(null);
  const [tab, setTab] = useState(0);
  const [channel, setChannel] = useState<any>(null);
  const [playlists, setPlaylists] = useState<any[]>([]);
  const [videos, setVideos] = useState<any[]>([]);
  const [plPage, setPlPage] = useState(1);
  const [plCount, setPlCount] = useState(0);
  const [vidPage, setVidPage] = useState(1);
  const [vidCount, setVidCount] = useState(0);
  const pageSize = 24;
  const plOrdering = '-yt_published_at';
  const vidOrdering = '-published_at';
  const [loading, setLoading] = useState(false);
  const [syncBusy, setSyncBusy] = useState(false);
  const [busyIds, setBusyIds] = useState<Set<string>>(new Set());
  const [err, setErr] = useState<string | null>(null);
  const [plQuery, setPlQuery] = useState('');
  const [vidQuery, setVidQuery] = useState('');

  const isStaff = useMemo(() => !!(user && ((user as any).is_staff || (Array.isArray((user as any).roles) && (user as any).roles.includes('AdminFrontend')))), [user]);

  useEffect(() => { (async () => { try { setUser(await getCurrentUser()); } catch {} })(); }, []);

  const load = async () => {
    if (!slug) return;
    setLoading(true);
    try {
      const [ch, pls, vids] = await Promise.all([
        api.get(`/channels/${encodeURIComponent(slug)}/`).catch(()=>({data:null})),
        api.get('/channels/playlists/', { params: { channel: slug, page: plPage, page_size: pageSize, ordering: plOrdering, search: plQuery || undefined } }).catch(()=>({data:{results:[], count: 0}})),
        api.get('/channels/videos/', { params: { channel: slug, page: vidPage, page_size: pageSize, ordering: vidOrdering, search: vidQuery || undefined } }).catch(()=>({data:{results:[], count: 0}})),
      ]);
      setChannel(ch.data);
      const plsList = Array.isArray(pls.data) ? pls.data : (pls.data?.results || []);
      const vidsList = Array.isArray(vids.data) ? vids.data : (vids.data?.results || []);
      setPlaylists(plsList);
      setVideos(vidsList);
      setPlCount(typeof pls.data?.count === 'number' ? pls.data.count : plsList.length);
      setVidCount(typeof vids.data?.count === 'number' ? vids.data.count : vidsList.length);
    } finally { setLoading(false); }
  };

  useEffect(()=>{ load(); }, [slug, plPage, vidPage, plQuery, vidQuery]);

  // Reset playlist page when search changes
  useEffect(()=>{ setPlPage(1); }, [plQuery]);
  // Reset videos page when search changes
  useEffect(()=>{ setVidPage(1); }, [vidQuery]);

  const syncPlaylists = async () => {
    if (!slug) return; setSyncBusy(true);
    try { await api.post(`/channels/${encodeURIComponent(slug)}/yt/sync-playlists/`); await load(); } finally { setSyncBusy(false); }
  };
  const syncAll = async () => {
    if (!slug) return; setSyncBusy(true);
    try { await api.post(`/channels/${encodeURIComponent(slug)}/yt/sync-all/`); await load(); } finally { setSyncBusy(false); }
  };

  const togglePlaylist = async (pl: any, next: boolean) => {
    const key = `${pl.id}-${next?'act':'deact'}`;
    setBusyIds(prev => new Set(prev).add(key));
    try {
      await api.post(`/channels/playlists/${encodeURIComponent(pl.id)}/${next? 'activate':'deactivate'}/`);
      await load();
    } catch (e:any) {
      setErr(e?.response?.data?.detail || 'Failed to update playlist');
    } finally {
      setBusyIds(prev => { const n = new Set(prev); n.delete(key); return n; });
    }
  };

  return (
    <Stack spacing={2}>
      <Stack direction="row" spacing={2} alignItems="center">
        <Typography variant="h5">Channel: {slug}</Typography>
        <Tooltip title="Reload"><span><IconButton onClick={load} disabled={loading}><RefreshIcon/></IconButton></span></Tooltip>
        {isStaff && (
          <Stack direction="row" spacing={1}>
            <Tooltip title="Sync playlists from YouTube"><span><Button size="small" variant="outlined" startIcon={<PlaylistAddIcon/>} onClick={syncPlaylists} disabled={syncBusy}>Sync Playlists</Button></span></Tooltip>
            <Tooltip title="Sync playlists then videos from YouTube"><span><Button size="small" variant="contained" startIcon={<SyncIcon/>} onClick={syncAll} disabled={syncBusy}>Sync All</Button></span></Tooltip>
          </Stack>
        )}
      </Stack>

      {channel && (
        <Card>
          <CardContent>
            <Stack direction="row" spacing={2} alignItems="center">
              {/* eslint-disable-next-line jsx-a11y/img-redundant-alt */}
              <img src={`/api/channels/${encodeURIComponent(slug!)}/logo/`} alt="logo" style={{ height: 48 }} onError={(e:any)=>{ e.currentTarget.style.visibility='hidden'; }} />
              <Box>
                <Typography variant="subtitle1">{channel.name_en || channel.name_am || channel.id_slug}</Typography>
                <Typography variant="caption" color="text.secondary">{channel.id_slug}</Typography>
              </Box>
              <Chip size="small" color={channel.is_active ? 'success' : 'default'} label={channel.is_active ? 'Active' : 'Inactive'} />
            </Stack>
          </CardContent>
        </Card>
      )}

      <Tabs value={tab} onChange={(_,v)=>setTab(v)}>
        <Tab label={`Playlists (${plCount})`} />
        <Tab label={`Videos (${vidCount})`} />
      </Tabs>

      {tab === 0 && (
        <Grid container spacing={2}>
          <Grid item xs={12}>
            <TextField
              size="small"
              fullWidth
              placeholder="Search by playlist title"
              value={plQuery}
              onChange={(e)=>setPlQuery(e.target.value)}
            />
          </Grid>
          {playlists.map((pl:any) => (
            <Grid item xs={12} sm={6} md={4} lg={3} key={pl.id}>
              <Card>
                <Box sx={{ height: 140, display:'flex', alignItems:'center', justifyContent:'center', bgcolor:'action.hover' }}>
                  {/* eslint-disable-next-line jsx-a11y/img-redundant-alt */}
                  {pl.thumbnail_url ? (
                    <img src={pl.thumbnail_url} alt="thumbnail" style={{ maxHeight: 120, maxWidth:'90%', objectFit:'cover' }} />
                  ) : (
                    <img src={pl.channel_logo_url || ''} alt="channel logo" style={{ maxHeight: 120, maxWidth:'90%', objectFit:'contain' }} />
                  )}
                </Box>
                <CardContent>
                  <Typography variant="subtitle1" noWrap title={pl.title}>{pl.title}</Typography>
                  <Typography variant="caption" color="text.secondary">{pl.channel}</Typography>
                  <Box sx={{ mt: 1, display:'flex', gap:1, alignItems:'center', justifyContent:'space-between' }}>
                    <Stack direction="row" spacing={1} alignItems="center">
                      <Chip size="small" label={`${pl.item_count}`} />
                      <Chip size="small" color={pl.is_active ? 'success' : 'default'} label={pl.is_active ? 'Active' : 'Inactive'} />
                    </Stack>
                    {isStaff && (
                      <span>
                        <Button size="small" variant={pl.is_active? 'outlined':'contained'} color={pl.is_active? 'warning':'primary'} disabled={busyIds.has(`${pl.id}-${pl.is_active?'deact':'act'}`)} onClick={()=>togglePlaylist(pl, !pl.is_active)}>
                          {pl.is_active? 'Deactivate':'Activate'}
                        </Button>
                      </span>
                    )}
                  </Box>
                </CardContent>
              </Card>
            </Grid>
          ))}
          <Grid item xs={12}>
            <Box sx={{ display:'flex', justifyContent:'center', my:2 }}>
              <Pagination page={plPage} onChange={(_,p)=>setPlPage(p)} count={Math.max(1, Math.ceil(plCount / pageSize))} color="primary" />
            </Box>
          </Grid>
        </Grid>
      )}

      {tab === 1 && (
        <Grid container spacing={2}>
          <Grid item xs={12}>
            <TextField
              size="small"
              fullWidth
              placeholder="Search videos by title or channel"
              value={vidQuery}
              onChange={(e)=>setVidQuery(e.target.value)}
            />
          </Grid>
          {videos.map((v:any) => (
            <Grid item xs={12} sm={6} md={4} lg={3} key={v.id}>
              <Card>
                <Box sx={{ height: 140, display:'flex', alignItems:'center', justifyContent:'center', bgcolor:'action.hover' }}>
                  {(() => {
                    const t = v.thumbnails || {}; const order = ['maxres','standard','high','medium','default'];
                    let url: string | null = null;
                    for (const k of order) { const x = t[k]; if (x && typeof x.url === 'string') { url = x.url; break; } }
                    if (!url && typeof t.url === 'string') url = t.url;
                    return url ? <img src={url} alt="thumb" style={{ maxHeight: 120, maxWidth:'90%', objectFit:'cover' }} /> : null;
                  })()}
                </Box>
                <CardContent>
                  <Typography variant="subtitle1" noWrap title={v.title}>{v.title || v.video_id}</Typography>
                  <Typography variant="caption" color="text.secondary">{v.channel} · PL {v.playlist}</Typography>
                  <Box sx={{ mt: 1 }}>
                    <Chip size="small" color={v.is_active ? 'success' : 'default'} label={v.is_active ? 'Active' : 'Inactive'} />
                  </Box>
                </CardContent>
              </Card>
            </Grid>
          ))}
          <Grid item xs={12}>
            <Box sx={{ display:'flex', justifyContent:'center', my:2 }}>
              <Pagination page={vidPage} onChange={(_,p)=>setVidPage(p)} count={Math.max(1, Math.ceil(vidCount / pageSize))} color="primary" />
            </Box>
          </Grid>
        </Grid>
      )}

      <Snackbar open={!!err} autoHideDuration={4000} onClose={()=>setErr(null)}>
        <Alert severity="error" variant="filled" onClose={()=>setErr(null)} sx={{ width:'100%' }}>{err}</Alert>
      </Snackbar>
    </Stack>
  );
};

export default ChannelDetail;
