import React, { useEffect, useMemo, useState } from 'react';
import { Box, Button, Chip, Dialog, DialogActions, DialogContent, DialogTitle, Divider, FormControlLabel, IconButton, Stack, Switch, Tab, Tabs, TextField, Tooltip, Typography, Snackbar, Alert, Pagination } from '@mui/material';
import AddIcon from '@mui/icons-material/Add';
import DeleteIcon from '@mui/icons-material/Delete';
import EditIcon from '@mui/icons-material/Edit';
import RefreshIcon from '@mui/icons-material/Refresh';
import api from '../services/api';
import { getCurrentUser, User } from '../services/auth';

// Live
interface LiveItem {
  id: number;
  channel: number;
  title: string;
  description?: string;
  poster_url?: string;
  playback_url?: string;
  playback_type?: string;
  drm?: any;
  is_active: boolean;
  is_previewable: boolean;
}

// LiveRadio
interface RadioItem {
  id: number;
  name: string;
  slug: string;
  description?: string;
  language?: string;
  country?: string;
  stream_url: string;
  backup_stream_url?: string;
  bitrate?: number;
  format?: string;
  is_active: boolean;
  is_verified: boolean;
  priority?: number;
}

function useIsStaff() {
  const [user, setUser] = useState<User | null>(null);
  useEffect(() => { (async () => { try { setUser(await getCurrentUser()); } catch {} })(); }, []);
  return useMemo(() => !!(user && ((user as any).is_staff || (Array.isArray((user as any).roles) && (user as any).roles.includes('AdminFrontend')))), [user]);
}

const LiveAdmin: React.FC = () => {
  const isStaff = useIsStaff();
  const [tab, setTab] = useState(0);
  const [err, setErr] = useState<string | null>(null);

  return (
    <Stack spacing={2}>
      <Typography variant="h5">Live</Typography>
      <Tabs value={tab} onChange={(_, v)=>setTab(v)}>
        <Tab label="Live TV" />
        <Tab label="Live Radio" />
      </Tabs>
      <Divider />
      {tab === 0 ? <LiveTvSection isStaff={isStaff} onError={setErr} /> : <LiveRadioSection isStaff={isStaff} onError={setErr} />}
      <Snackbar open={!!err} autoHideDuration={4000} onClose={()=>setErr(null)}>
        <Alert severity="error" variant="filled" onClose={()=>setErr(null)} sx={{ width:'100%' }}>{err}</Alert>
      </Snackbar>
    </Stack>
  );
};

function LiveTvSection({ isStaff, onError }: { isStaff: boolean; onError: (m: string|null)=>void; }) {
  const [items, setItems] = useState<LiveItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<LiveItem | null>(null);
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [count, setCount] = useState(0);

  const load = async () => {
    setLoading(true);
    try {
      const params: any = { ordering: '-updated_at', page };
      if (search.trim()) params.search = search.trim();
      const { data } = await api.get('/live/', { params });
      const list = Array.isArray(data) ? data : (data?.results || []);
      setItems(list);
      setCount(typeof data?.count === 'number' ? data.count : list.length);
    } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to load Live'); } finally { setLoading(false); }
  };
  useEffect(()=>{ load(); }, [page]);

  const handleSave = async (payload: Partial<LiveItem>) => {
    try {
      if (editing?.id) {
        await api.patch(`/live/${editing.id}/`, payload);
      } else {
        await api.post('/live/', payload);
      }
      setOpen(false); setEditing(null); await load();
    } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to save Live'); }
  };

  const handleDelete = async (id: number) => {
    if (!window.confirm('Delete this Live?')) return;
    try { await api.delete(`/live/${id}/`); await load(); } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to delete Live'); }
  };

  return (
    <Stack spacing={2}>
      <Stack direction="row" alignItems="center" spacing={1} sx={{ flexWrap:'wrap', rowGap: 1 }}>
        <TextField size="small" label="Search title or channel" value={search} onChange={e=>setSearch(e.target.value)} onKeyDown={(e)=>{ if (e.key==='Enter') { setPage(1); load(); } }} />
        <Box sx={{ flexGrow: 1 }} />
        {isStaff && (
          <Button startIcon={<AddIcon />} variant="contained" onClick={()=>{ setEditing(null); setOpen(true); }}>Add Live</Button>
        )}
        <Tooltip title="Reload"><span><IconButton onClick={load} disabled={loading}><RefreshIcon/></IconButton></span></Tooltip>
      </Stack>
      <Stack spacing={1}>
        {items.map(it => (
          <Stack key={it.id} direction="row" spacing={2} alignItems="center" sx={{ p:1, border:'1px solid', borderColor:'divider', borderRadius:1, minWidth:0 }}>
            <Box sx={{ flex: 1, minWidth:0 }}>
              <Typography variant="subtitle1" noWrap title={it.title}>{it.title}</Typography>
              <Typography variant="caption" color="text.secondary" noWrap title={it.playback_url}>{it.playback_url}</Typography>
            </Box>
            <Chip size="small" color={it.is_active ? 'success':'default'} label={it.is_active ? 'Active':'Inactive'} />
            {isStaff && (
              <Stack direction="row" spacing={1}>
                <IconButton onClick={()=>{ setEditing(it); setOpen(true); }}><EditIcon/></IconButton>
                <IconButton onClick={()=>handleDelete(it.id)} color="error"><DeleteIcon/></IconButton>
              </Stack>
            )}
          </Stack>
        ))}
      </Stack>
      <Box sx={{ display:'flex', justifyContent:'center' }}>
        <Pagination page={page} onChange={(_,p)=>setPage(p)} count={Math.max(1, Math.ceil(count / 24))} color="primary" />
      </Box>
      <LiveDialog open={open} onClose={()=>{ setOpen(false); setEditing(null); }} initial={editing || undefined} onSave={handleSave} />
    </Stack>
  );
}

function LiveDialog({ open, onClose, initial, onSave }: { open: boolean; onClose: ()=>void; initial?: Partial<LiveItem>; onSave: (p: Partial<LiveItem>)=>void; }) {
  const [title, setTitle] = useState(initial?.title || '');
  const [channel, setChannel] = useState(initial?.channel || (undefined as any));
  const [playbackUrl, setPlaybackUrl] = useState(initial?.playback_url || '');
  const [playbackType, setPlaybackType] = useState(initial?.playback_type || 'hls');
  const [posterUrl, setPosterUrl] = useState(initial?.poster_url || '');
  const [isActive, setIsActive] = useState(!!initial?.is_active);
  const [isPreview, setIsPreview] = useState(!!initial?.is_previewable);

  useEffect(()=>{
    setTitle(initial?.title || '');
    setChannel(initial?.channel || (undefined as any));
    setPlaybackUrl(initial?.playback_url || '');
    setPlaybackType(initial?.playback_type || 'hls');
    setPosterUrl(initial?.poster_url || '');
    setIsActive(!!initial?.is_active);
    setIsPreview(!!initial?.is_previewable);
  }, [initial]);

  const submit = () => {
    if (!channel) { alert('Channel id is required'); return; }
    onSave({ title, channel, playback_url: playbackUrl, playback_type: playbackType, poster_url: posterUrl, is_active: isActive, is_previewable: isPreview });
  };

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>{initial?.id ? 'Edit Live' : 'Add Live'}</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt:1 }}>
          <TextField label="Channel ID" type="number" value={channel ?? ''} onChange={e=>setChannel(Number(e.target.value))} />
          <TextField label="Title" value={title} onChange={e=>setTitle(e.target.value)} />
          <TextField label="Playback URL" value={playbackUrl} onChange={e=>setPlaybackUrl(e.target.value)} />
          <TextField label="Playback Type" value={playbackType} onChange={e=>setPlaybackType(e.target.value)} />
          <TextField label="Poster URL" value={posterUrl} onChange={e=>setPosterUrl(e.target.value)} />
          <FormControlLabel control={<Switch checked={isActive} onChange={e=>setIsActive(e.target.checked)} />} label="Active" />
          <FormControlLabel control={<Switch checked={isPreview} onChange={e=>setIsPreview(e.target.checked)} />} label="Previewable" />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" onClick={submit}>Save</Button>
      </DialogActions>
    </Dialog>
  );
}

function LiveRadioSection({ isStaff, onError }: { isStaff: boolean; onError: (m: string|null)=>void; }) {
  const [items, setItems] = useState<RadioItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<RadioItem | null>(null);
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [count, setCount] = useState(0);

  const load = async () => {
    setLoading(true);
    try {
      const params: any = { ordering: '-updated_at', page };
      if (search.trim()) params.search = search.trim();
      const { data } = await api.get('/live/radios/', { params });
      const list = Array.isArray(data) ? data : (data?.results || []);
      setItems(list);
      setCount(typeof data?.count === 'number' ? data.count : list.length);
    } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to load Radios'); } finally { setLoading(false); }
  };
  useEffect(()=>{ load(); }, [page]);

  const handleSave = async (payload: Partial<RadioItem>) => {
    try {
      if (editing?.id) {
        await api.patch(`/live/radios/${editing.id}/`, payload);
      } else {
        await api.post('/live/radios/', payload);
      }
      setOpen(false); setEditing(null); await load();
    } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to save Radio'); }
  };

  const handleDelete = async (id: number) => {
    if (!window.confirm('Delete this Radio?')) return;
    try { await api.delete(`/live/radios/${id}/`); await load(); } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to delete Radio'); }
  };

  return (
    <Stack spacing={2}>
      <Stack direction="row" alignItems="center" spacing={1} sx={{ flexWrap:'wrap', rowGap: 1 }}>
        <TextField size="small" label="Search name, slug, language, country" value={search} onChange={e=>setSearch(e.target.value)} onKeyDown={(e)=>{ if (e.key==='Enter') { setPage(1); load(); } }} />
        <Box sx={{ flexGrow: 1 }} />
        {isStaff && (
          <Button startIcon={<AddIcon />} variant="contained" onClick={()=>{ setEditing(null); setOpen(true); }}>Add Radio</Button>
        )}
        <Tooltip title="Reload"><span><IconButton onClick={load} disabled={loading}><RefreshIcon/></IconButton></span></Tooltip>
      </Stack>
      <Stack spacing={1}>
        {items.map(it => (
          <Stack key={it.id} direction="row" spacing={2} alignItems="center" sx={{ p:1, border:'1px solid', borderColor:'divider', borderRadius:1, minWidth:0 }}>
            <Box sx={{ flex: 1, minWidth:0 }}>
              <Typography variant="subtitle1" noWrap title={it.name}>{it.name}</Typography>
              <Typography variant="caption" color="text.secondary" noWrap title={it.stream_url}>{it.stream_url}</Typography>
            </Box>
            <Chip size="small" color={it.is_active ? 'success':'default'} label={it.is_active ? 'Active':'Inactive'} />
            <Chip size="small" color={it.is_verified ? 'primary':'default'} label={it.is_verified ? 'Verified':'Unverified'} />
            {isStaff && (
              <Stack direction="row" spacing={1}>
                <IconButton onClick={()=>{ setEditing(it); setOpen(true); }}><EditIcon/></IconButton>
                <IconButton onClick={()=>handleDelete(it.id)} color="error"><DeleteIcon/></IconButton>
              </Stack>
            )}
          </Stack>
        ))}
      </Stack>
      <Box sx={{ display:'flex', justifyContent:'center' }}>
        <Pagination page={page} onChange={(_,p)=>setPage(p)} count={Math.max(1, Math.ceil(count / 24))} color="primary" />
      </Box>
      <RadioDialog open={open} onClose={()=>{ setOpen(false); setEditing(null); }} initial={editing || undefined} onSave={handleSave} />
    </Stack>
  );
}

function RadioDialog({ open, onClose, initial, onSave }: { open: boolean; onClose: ()=>void; initial?: Partial<RadioItem>; onSave: (p: Partial<RadioItem>)=>void; }) {
  const [name, setName] = useState(initial?.name || '');
  const [slug, setSlug] = useState(initial?.slug || '');
  const [streamUrl, setStreamUrl] = useState(initial?.stream_url || '');
  const [backupStreamUrl, setBackupStreamUrl] = useState(initial?.backup_stream_url || '');
  const [bitrate, setBitrate] = useState<number | ''>(initial?.bitrate ?? '');
  const [format, setFormat] = useState(initial?.format || '');
  const [isActive, setIsActive] = useState(!!initial?.is_active);
  const [isVerified, setIsVerified] = useState(!!initial?.is_verified);

  useEffect(()=>{
    setName(initial?.name || '');
    setSlug(initial?.slug || '');
    setStreamUrl(initial?.stream_url || '');
    setBackupStreamUrl(initial?.backup_stream_url || '');
    setBitrate(initial?.bitrate ?? '');
    setFormat(initial?.format || '');
    setIsActive(!!initial?.is_active);
    setIsVerified(!!initial?.is_verified);
  }, [initial]);

  const submit = () => {
    if (!name.trim() || !slug.trim() || !streamUrl.trim()) { alert('Name, slug, and stream URL are required'); return; }
    onSave({ name: name.trim(), slug: slug.trim(), stream_url: streamUrl.trim(), backup_stream_url: backupStreamUrl.trim() || undefined, bitrate: typeof bitrate==='number'?bitrate: undefined, format: format.trim() || undefined, is_active: isActive, is_verified: isVerified });
  };

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>{initial?.id ? 'Edit Radio' : 'Add Radio'}</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt:1 }}>
          <TextField label="Name" value={name} onChange={e=>setName(e.target.value)} />
          <TextField label="Slug" value={slug} onChange={e=>setSlug(e.target.value)} />
          <TextField label="Stream URL" value={streamUrl} onChange={e=>setStreamUrl(e.target.value)} />
          <TextField label="Backup Stream URL" value={backupStreamUrl} onChange={e=>setBackupStreamUrl(e.target.value)} />
          <TextField label="Bitrate" type="number" value={bitrate} onChange={e=>setBitrate(e.target.value===''? '': Number(e.target.value))} />
          <TextField label="Format" value={format} onChange={e=>setFormat(e.target.value)} />
          <FormControlLabel control={<Switch checked={isActive} onChange={e=>setIsActive(e.target.checked)} />} label="Active" />
          <FormControlLabel control={<Switch checked={isVerified} onChange={e=>setIsVerified(e.target.checked)} />} label="Verified" />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" onClick={submit}>Save</Button>
      </DialogActions>
    </Dialog>
  );
}

export default LiveAdmin;
