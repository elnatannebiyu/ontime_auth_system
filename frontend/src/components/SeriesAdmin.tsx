import React, { useEffect, useMemo, useState } from 'react';
import { Alert, Box, Button, Chip, Dialog, DialogActions, DialogContent, DialogTitle, Divider, FormControlLabel, IconButton, Pagination, Snackbar, Stack, Switch, Tab, Tabs, TextField, Tooltip, Typography } from '@mui/material';
import AddIcon from '@mui/icons-material/Add';
import DeleteIcon from '@mui/icons-material/Delete';
import EditIcon from '@mui/icons-material/Edit';
import RefreshIcon from '@mui/icons-material/Refresh';
import api from '../services/api';
import { getCurrentUser, User } from '../services/auth';

interface ShowItem {
  id: number;
  slug: string;
  title: string;
  channel: number;
  is_active: boolean;
}

interface SeasonItem {
  id: number;
  show: string; // slug
  number: number;
  title?: string;
  yt_playlist_id?: string;
  is_enabled: boolean;
}

interface EpisodeItem {
  id: number;
  season: number; // id
  title: string;
  source_video_id: string;
  source_published_at?: string | null;
  episode_number?: number | null;
  visible: boolean;
  status: string;
}

interface CategoryItem {
  id?: number;
  name: string;
  slug: string;
  color?: string;
  description?: string;
  display_order?: number;
  is_active: boolean;
}

function useIsStaff() {
  const [user, setUser] = useState<User | null>(null);
  useEffect(() => { (async () => { try { setUser(await getCurrentUser()); } catch {} })(); }, []);
  return useMemo(() => !!(user && ((user as any).is_staff || (Array.isArray((user as any).roles) && (user as any).roles.includes('AdminFrontend')))), [user]);
}

const SeriesAdmin: React.FC = () => {
  const isStaff = useIsStaff();
  const [tab, setTab] = useState(0);
  const [err, setErr] = useState<string | null>(null);

  return (
    <Stack spacing={2}>
      <Typography variant="h5">Series</Typography>
      <Tabs value={tab} onChange={(_, v)=>setTab(v)}>
        <Tab label="Shows" />
        <Tab label="Seasons" />
        <Tab label="Episodes" />
        <Tab label="Categories" />
      </Tabs>
      <Divider />
      {tab === 0 && <ShowsSection isStaff={isStaff} onError={setErr} />}
      {tab === 1 && <SeasonsSection isStaff={isStaff} onError={setErr} />}
      {tab === 2 && <EpisodesSection isStaff={isStaff} onError={setErr} />}
      {tab === 3 && <CategoriesSection isStaff={isStaff} onError={setErr} />}
      <Snackbar open={!!err} autoHideDuration={4000} onClose={()=>setErr(null)}>
        <Alert severity="error" variant="filled" onClose={()=>setErr(null)} sx={{ width:'100%' }}>{err}</Alert>
      </Snackbar>
    </Stack>
  );
};

function ShowsSection({ isStaff, onError }: { isStaff: boolean; onError: (m: string|null)=>void; }) {
  const [items, setItems] = useState<ShowItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<ShowItem | null>(null);
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [count, setCount] = useState(0);

  const load = async () => {
    setLoading(true);
    try {
      const params: any = { ordering: 'title', page };
      if (search.trim()) params.search = search.trim();
      const { data } = await api.get('/series/shows/', { params });
      const list = Array.isArray(data) ? data : (data?.results || []);
      setItems(list);
      setCount(typeof data?.count === 'number' ? data.count : list.length);
    } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to load Shows'); } finally { setLoading(false); }
  };
  useEffect(()=>{ load(); }, [page]);

  const handleSave = async (payload: Partial<ShowItem>) => {
    try {
      if (editing?.slug) {
        await api.patch(`/series/shows/${encodeURIComponent(editing.slug)}/`, payload);
      } else {
        await api.post('/series/shows/', payload);
      }
      setOpen(false); setEditing(null); await load();
    } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to save Show'); }
  };

  const handleDelete = async (slug: string) => {
    if (!window.confirm('Delete this Show?')) return;
    try { await api.delete(`/series/shows/${encodeURIComponent(slug)}/`); await load(); } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to delete Show'); }
  };

  return (
    <Stack spacing={2}>
      <Stack direction="row" alignItems="center" spacing={1} sx={{ flexWrap:'wrap', rowGap:1 }}>
        <TextField size="small" label="Search title or slug" value={search} onChange={e=>setSearch(e.target.value)} onKeyDown={(e)=>{ if (e.key==='Enter') { setPage(1); load(); } }} />
        <Box sx={{ flexGrow: 1 }} />
        {isStaff && <Button startIcon={<AddIcon />} variant="contained" onClick={()=>{ setEditing(null); setOpen(true); }}>Add Show</Button>}
        <Tooltip title="Reload"><span><IconButton onClick={load} disabled={loading}><RefreshIcon/></IconButton></span></Tooltip>
      </Stack>
      <Stack spacing={1}>
        {items.map(it => (
          <Stack key={it.slug} direction="row" spacing={2} alignItems="center" sx={{ p:1, border:'1px solid', borderColor:'divider', borderRadius:1, minWidth:0 }}>
            <Box sx={{ flex: 1, minWidth:0 }}>
              <Typography variant="subtitle1" noWrap title={it.title}>{it.title}</Typography>
              <Typography variant="caption" color="text.secondary" noWrap title={it.slug} sx={{ fontFamily:'monospace' }}>{it.slug}</Typography>
            </Box>
            <Chip size="small" color={it.is_active ? 'success':'default'} label={it.is_active ? 'Active':'Inactive'} />
            {isStaff && (
              <Stack direction="row" spacing={1}>
                <IconButton onClick={()=>{ setEditing(it); setOpen(true); }}><EditIcon/></IconButton>
                <IconButton onClick={()=>handleDelete(it.slug)} color="error"><DeleteIcon/></IconButton>
              </Stack>
            )}
          </Stack>
        ))}
      </Stack>
      <Box sx={{ display:'flex', justifyContent:'center' }}>
        <Pagination page={page} onChange={(_,p)=>setPage(p)} count={Math.max(1, Math.ceil(count / 24))} color="primary" />
      </Box>
      <ShowDialog open={open} onClose={()=>{ setOpen(false); setEditing(null); }} initial={editing || undefined} onSave={handleSave} />
    </Stack>
  );
}

function ShowDialog({ open, onClose, initial, onSave }: { open: boolean; onClose: ()=>void; initial?: Partial<ShowItem>; onSave: (p: Partial<ShowItem>)=>void; }) {
  const [slug, setSlug] = useState(initial?.slug || '');
  const [title, setTitle] = useState(initial?.title || '');
  const [channel, setChannel] = useState<number | ''>(initial?.channel ?? '');
  const [isActive, setIsActive] = useState(!!initial?.is_active);

  useEffect(()=>{
    setSlug(initial?.slug || '');
    setTitle(initial?.title || '');
    setChannel(initial?.channel ?? '');
    setIsActive(!!initial?.is_active);
  }, [initial]);

  const submit = () => {
    if (!slug.trim() || !title.trim() || channel === '') { alert('Slug, title and channel id are required'); return; }
    onSave({ slug: slug.trim(), title: title.trim(), channel: typeof channel==='number'?channel:Number(channel), is_active: isActive });
  };

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>{initial?.slug ? 'Edit Show' : 'Add Show'}</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt:1 }}>
          <TextField label="Slug" value={slug} onChange={e=>setSlug(e.target.value)} disabled={!!initial?.slug} />
          <TextField label="Title" value={title} onChange={e=>setTitle(e.target.value)} />
          <TextField label="Channel ID" type="number" value={channel} onChange={e=>setChannel(e.target.value===''?'': Number(e.target.value))} />
          <FormControlLabel control={<Switch checked={isActive} onChange={e=>setIsActive(e.target.checked)} />} label="Active" />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" onClick={submit}>Save</Button>
      </DialogActions>
    </Dialog>
  );
}

function SeasonsSection({ isStaff, onError }: { isStaff: boolean; onError: (m: string|null)=>void; }) {
  const [items, setItems] = useState<SeasonItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<SeasonItem | null>(null);
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [count, setCount] = useState(0);

  const load = async () => {
    setLoading(true);
    try {
      const params: any = { ordering: 'number', page };
      if (search.trim()) params.search = search.trim();
      const { data } = await api.get('/series/seasons/', { params });
      const list = Array.isArray(data) ? data : (data?.results || []);
      setItems(list);
      setCount(typeof data?.count === 'number' ? data.count : list.length);
    } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to load Seasons'); } finally { setLoading(false); }
  };
  useEffect(()=>{ load(); }, [page]);

  const handleSave = async (payload: Partial<SeasonItem>) => {
    try {
      if (editing?.id) {
        await api.patch(`/series/seasons/${editing.id}/`, payload);
      } else {
        await api.post('/series/seasons/', payload);
      }
      setOpen(false); setEditing(null); await load();
    } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to save Season'); }
  };

  const handleDelete = async (id: number) => {
    if (!window.confirm('Delete this Season?')) return;
    try { await api.delete(`/series/seasons/${id}/`); await load(); } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to delete Season'); }
  };

  return (
    <Stack spacing={2}>
      <Stack direction="row" alignItems="center" spacing={1} sx={{ flexWrap:'wrap', rowGap:1 }}>
        <TextField size="small" label="Search by show slug or title" value={search} onChange={e=>setSearch(e.target.value)} onKeyDown={(e)=>{ if (e.key==='Enter') { setPage(1); load(); } }} />
        <Box sx={{ flexGrow: 1 }} />
        {isStaff && <Button startIcon={<AddIcon />} variant="contained" onClick={()=>{ setEditing(null); setOpen(true); }}>Add Season</Button>}
        <Tooltip title="Reload"><span><IconButton onClick={load} disabled={loading}><RefreshIcon/></IconButton></span></Tooltip>
      </Stack>
      <Stack spacing={1}>
        {items.map(it => (
          <Stack key={it.id} direction="row" spacing={2} alignItems="center" sx={{ p:1, border:'1px solid', borderColor:'divider', borderRadius:1, minWidth:0 }}>
            <Box sx={{ flex: 1, minWidth:0 }}>
              <Typography variant="subtitle1" noWrap title={`${it.show} • S${it.number}${it.title? ' • '+it.title:''}`}>{it.show} • S{it.number}{it.title? ` • ${it.title}`:''}</Typography>
              <Typography variant="caption" color="text.secondary" noWrap title={it.yt_playlist_id} sx={{ fontFamily:'monospace' }}>{it.yt_playlist_id}</Typography>
            </Box>
            <Chip size="small" color={it.is_enabled ? 'success':'default'} label={it.is_enabled ? 'Enabled':'Disabled'} />
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
      <SeasonDialog open={open} onClose={()=>{ setOpen(false); setEditing(null); }} initial={editing || undefined} onSave={handleSave} />
    </Stack>
  );
}

function SeasonDialog({ open, onClose, initial, onSave }: { open: boolean; onClose: ()=>void; initial?: Partial<SeasonItem>; onSave: (p: Partial<SeasonItem>)=>void; }) {
  const [show, setShow] = useState(initial?.show || '');
  const [number, setNumber] = useState<number | ''>(initial?.number ?? '');
  const [title, setTitle] = useState(initial?.title || '');
  const [playlist, setPlaylist] = useState(initial?.yt_playlist_id || '');
  const [enabled, setEnabled] = useState(!!initial?.is_enabled);

  useEffect(()=>{
    setShow(initial?.show || '');
    setNumber(initial?.number ?? '');
    setTitle(initial?.title || '');
    setPlaylist(initial?.yt_playlist_id || '');
    setEnabled(!!initial?.is_enabled);
  }, [initial]);

  const submit = () => {
    if (!show.trim() || number === '') { alert('Show slug and number are required'); return; }
    onSave({ show: show.trim(), number: typeof number==='number'? number:Number(number), title: title.trim() || undefined, yt_playlist_id: playlist.trim() || undefined, is_enabled: enabled });
  };

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>{initial?.id ? 'Edit Season' : 'Add Season'}</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt:1 }}>
          <TextField label="Show Slug" value={show} onChange={e=>setShow(e.target.value)} />
          <TextField label="Number" type="number" value={number} onChange={e=>setNumber(e.target.value===''? '': Number(e.target.value))} />
          <TextField label="Title" value={title} onChange={e=>setTitle(e.target.value)} />
          <TextField label="YouTube Playlist ID" value={playlist} onChange={e=>setPlaylist(e.target.value)} />
          <FormControlLabel control={<Switch checked={enabled} onChange={e=>setEnabled(e.target.checked)} />} label="Enabled" />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" onClick={submit}>Save</Button>
      </DialogActions>
    </Dialog>
  );
}

function EpisodesSection({ isStaff, onError }: { isStaff: boolean; onError: (m: string|null)=>void; }) {
  const [items, setItems] = useState<EpisodeItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<EpisodeItem | null>(null);
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [count, setCount] = useState(0);

  const load = async () => {
    setLoading(true);
    try {
      const params: any = { ordering: 'episode_number', page };
      if (search.trim()) params.search = search.trim();
      const { data } = await api.get('/series/episodes/', { params });
      const list = Array.isArray(data) ? data : (data?.results || []);
      setItems(list);
      setCount(typeof data?.count === 'number' ? data.count : list.length);
    } catch (e1:any) {
      try {
        const { data } = await api.get('/series/episodes/');
        const list = Array.isArray(data) ? data : (data?.results || []);
        setItems(list);
        setCount(typeof data?.count === 'number' ? data.count : list.length);
      } catch (e2:any) {
        onError(e2?.response?.data?.detail || e1?.response?.data?.detail || 'Failed to load Episodes');
      }
    } finally { setLoading(false); }
  };
  useEffect(()=>{ load(); }, [page]);

  const handleSave = async (payload: Partial<EpisodeItem>) => {
    try {
      if (editing?.id) {
        await api.patch(`/series/episodes/${editing.id}/`, payload);
      } else {
        await api.post('/series/episodes/', payload);
      }
      setOpen(false); setEditing(null); await load();
    } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to save Episode'); }
  };

  const handleDelete = async (id: number) => {
    if (!window.confirm('Delete this Episode?')) return;
    try { await api.delete(`/series/episodes/${id}/`); await load(); } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to delete Episode'); }
  };

  return (
    <Stack spacing={2}>
      <Stack direction="row" alignItems="center" spacing={1} sx={{ flexWrap:'wrap', rowGap:1 }}>
        <TextField size="small" label="Search title or video id" value={search} onChange={e=>setSearch(e.target.value)} onKeyDown={(e)=>{ if (e.key==='Enter') { setPage(1); load(); } }} />
        <Box sx={{ flexGrow: 1 }} />
        {isStaff && <Button startIcon={<AddIcon />} variant="contained" onClick={()=>{ setEditing(null); setOpen(true); }}>Add Episode</Button>}
        <Tooltip title="Reload"><span><IconButton onClick={load} disabled={loading}><RefreshIcon/></IconButton></span></Tooltip>
      </Stack>
      <Stack spacing={1}>
        {items.map(it => (
          <Stack key={it.id} direction="row" spacing={2} alignItems="center" sx={{ p:1, border:'1px solid', borderColor:'divider', borderRadius:1, minWidth:0 }}>
            <Box sx={{ flex: 1, minWidth:0 }}>
              <Typography variant="subtitle1" noWrap title={it.title}>{it.title}</Typography>
              <Typography variant="caption" color="text.secondary" noWrap title={`Season #${it.season} • ${it.source_video_id}`} sx={{ fontFamily:'monospace' }}>Season #{it.season} • {it.source_video_id}</Typography>
            </Box>
            <Chip size="small" color={it.visible ? 'success':'default'} label={it.visible ? 'Visible':'Hidden'} />
            <Chip size="small" label={it.status} />
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
      <EpisodeDialog open={open} onClose={()=>{ setOpen(false); setEditing(null); }} initial={editing || undefined} onSave={handleSave} />
    </Stack>
  );
}

function EpisodeDialog({ open, onClose, initial, onSave }: { open: boolean; onClose: ()=>void; initial?: Partial<EpisodeItem>; onSave: (p: Partial<EpisodeItem>)=>void; }) {
  const [season, setSeason] = useState<number | ''>(initial?.season ?? '');
  const [title, setTitle] = useState(initial?.title || '');
  const [videoId, setVideoId] = useState(initial?.source_video_id || '');
  const [publishedAt, setPublishedAt] = useState<string>(initial?.source_published_at || '');
  const [epNum, setEpNum] = useState<number | ''>(initial?.episode_number ?? '');
  const [visible, setVisible] = useState(!!initial?.visible);
  const [status, setStatus] = useState(initial?.status || 'published');

  useEffect(()=>{
    setSeason(initial?.season ?? '');
    setTitle(initial?.title || '');
    setVideoId(initial?.source_video_id || '');
    setPublishedAt(initial?.source_published_at || '');
    setEpNum(initial?.episode_number ?? '');
    setVisible(!!initial?.visible);
    setStatus(initial?.status || 'published');
  }, [initial]);

  const submit = () => {
    if (season === '' || !title.trim() || !videoId.trim()) { alert('Season id, title, and source video id are required'); return; }
    onSave({ season: typeof season==='number'?season:Number(season), title: title.trim(), source_video_id: videoId.trim(), source_published_at: publishedAt || undefined, episode_number: typeof epNum==='number'?epNum: (epNum===''? undefined: Number(epNum)), visible, status });
  };

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>{initial?.id ? 'Edit Episode' : 'Add Episode'}</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt:1 }}>
          <TextField label="Season ID" type="number" value={season} onChange={e=>setSeason(e.target.value===''?'': Number(e.target.value))} />
          <TextField label="Title" value={title} onChange={e=>setTitle(e.target.value)} />
          <TextField label="Source Video ID" value={videoId} onChange={e=>setVideoId(e.target.value)} />
          <TextField label="Source Published At (ISO)" value={publishedAt} onChange={e=>setPublishedAt(e.target.value)} />
          <TextField label="Episode Number" type="number" value={epNum} onChange={e=>setEpNum(e.target.value===''?'': Number(e.target.value))} />
          <FormControlLabel control={<Switch checked={visible} onChange={e=>setVisible(e.target.checked)} />} label="Visible" />
          <TextField label="Status" value={status} onChange={e=>setStatus(e.target.value)} />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" onClick={submit}>Save</Button>
      </DialogActions>
    </Dialog>
  );
}

function CategoriesSection({ isStaff, onError }: { isStaff: boolean; onError: (m: string|null)=>void; }) {
  const [items, setItems] = useState<CategoryItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<CategoryItem | null>(null);
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [count, setCount] = useState(0);

  const load = async () => {
    setLoading(true);
    try {
      const params: any = { ordering: 'display_order,name', page };
      if (search.trim()) params.search = search.trim();
      const { data } = await api.get('/series/categories/', { params });
      const list = Array.isArray(data) ? data : (data?.results || []);
      setItems(list);
      setCount(typeof data?.count === 'number' ? data.count : list.length);
    } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to load Categories'); } finally { setLoading(false); }
  };
  useEffect(()=>{ load(); }, [page]);

  const handleSave = async (payload: Partial<CategoryItem>) => {
    try {
      if (editing?.id) {
        await api.patch(`/series/categories/${editing.id}/`, payload);
      } else {
        await api.post('/series/categories/', payload);
      }
      setOpen(false); setEditing(null); await load();
    } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to save Category'); }
  };

  const handleDelete = async (id?: number) => {
    if (!id) return;
    if (!window.confirm('Delete this Category?')) return;
    try { await api.delete(`/series/categories/${id}/`); await load(); } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to delete Category'); }
  };

  return (
    <Stack spacing={2}>
      <Stack direction="row" alignItems="center" spacing={1} sx={{ flexWrap:'wrap', rowGap:1 }}>
        <TextField size="small" label="Search name or slug" value={search} onChange={e=>setSearch(e.target.value)} onKeyDown={(e)=>{ if (e.key==='Enter') { setPage(1); load(); } }} />
        <Box sx={{ flexGrow: 1 }} />
        {isStaff && <Button startIcon={<AddIcon />} variant="contained" onClick={()=>{ setEditing(null); setOpen(true); }}>Add Category</Button>}
        <Tooltip title="Reload"><span><IconButton onClick={load} disabled={loading}><RefreshIcon/></IconButton></span></Tooltip>
      </Stack>
      <Stack spacing={1}>
        {items.map(it => (
          <Stack key={`${it.slug}-${it.name}`} direction="row" spacing={2} alignItems="center" sx={{ p:1, border:'1px solid', borderColor:'divider', borderRadius:1, minWidth:0 }}>
            <Box sx={{ flex: 1, minWidth:0 }}>
              <Typography variant="subtitle1" noWrap title={it.name}>{it.name}</Typography>
              <Typography variant="caption" color="text.secondary" noWrap title={it.slug} sx={{ fontFamily:'monospace' }}>{it.slug}</Typography>
            </Box>
            <Chip size="small" color={it.is_active ? 'success':'default'} label={it.is_active ? 'Active':'Inactive'} />
            {isStaff && (
              <Stack direction="row" spacing={1}>
                <IconButton onClick={()=>{ setEditing(it); setOpen(true); }}><EditIcon/></IconButton>
                <IconButton onClick={()=>handleDelete((it as any).id)} color="error"><DeleteIcon/></IconButton>
              </Stack>
            )}
          </Stack>
        ))}
      </Stack>
      <Box sx={{ display:'flex', justifyContent:'center' }}>
        <Pagination page={page} onChange={(_,p)=>setPage(p)} count={Math.max(1, Math.ceil(count / 24))} color="primary" />
      </Box>
      <CategoryDialog open={open} onClose={()=>{ setOpen(false); setEditing(null); }} initial={editing || undefined} onSave={handleSave} />
    </Stack>
  );
}

function CategoryDialog({ open, onClose, initial, onSave }: { open: boolean; onClose: ()=>void; initial?: Partial<CategoryItem>; onSave: (p: Partial<CategoryItem>)=>void; }) {
  const [name, setName] = useState(initial?.name || '');
  const [slug, setSlug] = useState(initial?.slug || '');
  const [color, setColor] = useState(initial?.color || '');
  const [desc, setDesc] = useState(initial?.description || '');
  const [order, setOrder] = useState<number | ''>(initial?.display_order ?? '');
  const [active, setActive] = useState(!!initial?.is_active);

  useEffect(()=>{
    setName(initial?.name || '');
    setSlug(initial?.slug || '');
    setColor(initial?.color || '');
    setDesc(initial?.description || '');
    setOrder(initial?.display_order ?? '');
    setActive(!!initial?.is_active);
  }, [initial]);

  const submit = () => {
    if (!name.trim() || !slug.trim()) { alert('Name and slug are required'); return; }
    onSave({ name: name.trim(), slug: slug.trim(), color: color.trim() || undefined, description: desc.trim() || undefined, display_order: typeof order==='number'?order: (order===''? undefined: Number(order)), is_active: active });
  };

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>{initial?.id ? 'Edit Category' : 'Add Category'}</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt:1 }}>
          <TextField label="Name" value={name} onChange={e=>setName(e.target.value)} />
          <TextField label="Slug" value={slug} onChange={e=>setSlug(e.target.value)} />
          <TextField label="Color" type="color" value={color || '#000000'} onChange={e=>setColor(e.target.value)} sx={{ width: 140 }} />
          <TextField label="Description" value={desc} onChange={e=>setDesc(e.target.value)} />
          <TextField label="Display Order" type="number" value={order} onChange={e=>setOrder(e.target.value===''? '': Number(e.target.value))} />
          <FormControlLabel control={<Switch checked={active} onChange={e=>setActive(e.target.checked)} />} label="Active" />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" onClick={submit}>Save</Button>
      </DialogActions>
    </Dialog>
  );
}

export default SeriesAdmin;
