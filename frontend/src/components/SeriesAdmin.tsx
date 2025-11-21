import React, { useEffect, useMemo, useState } from 'react';
import { Alert, Box, Button, Chip, Dialog, DialogActions, DialogContent, DialogTitle, Divider, FormControlLabel, IconButton, MenuItem, Pagination, Select, Snackbar, Stack, Switch, Tab, Tabs, TextField, Tooltip, Typography, Collapse } from '@mui/material';
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
  // Channel FK numeric primary key
  channel: number;
  is_active: boolean;
  categories?: { slug: string; name: string }[];
}

interface ChannelOption {
  id: string; // id_slug
  name: string;
  slug?: string;
  is_active: boolean;
}

interface SeasonItem {
  id: number;
  show: string; // slug
  show_title?: string;
  number: number;
  title?: string;
  yt_playlist_id?: string;
  cover_image?: string;
  last_synced_at?: string | null;
  is_enabled: boolean;
}

interface ShowChoice {
  slug: string;
  title: string;
  channel?: string; // channel id_slug
}

interface PlaylistChoice {
  id: string;   // PL...
  title: string;
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

const SHOWS_PAGE_SIZE = 20;
const EPISODES_PAGE_SIZE = 200;

function useIsStaff() {
  const [user, setUser] = useState<User | null>(null);
  useEffect(() => { (async () => { try { setUser(await getCurrentUser()); } catch {} })(); }, []);
  return useMemo(() => !!(user && (Array.isArray((user as any).roles) && (user as any).roles.includes('AdminFrontend'))), [user]);
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
      const params: any = { ordering: 'title', page, page_size: SHOWS_PAGE_SIZE };
      if (search.trim()) params.search = search.trim();
      const { data } = await api.get('/series/shows/', { params });
      const list = Array.isArray(data) ? data : (data?.results || []);
      setItems(list);
      setCount(typeof data?.count === 'number' ? data.count : list.length);
    } catch (e:any) { onError(e?.response?.data?.detail || 'Failed to load Shows'); } finally { setLoading(false); }
  };
  useEffect(()=>{ load(); }, [page]);

  const handleSave = async (payload: any) => {
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
        <Pagination page={page} onChange={(_,p)=>setPage(p)} count={Math.max(1, Math.ceil(count / SHOWS_PAGE_SIZE))} color="primary" />
      </Box>
      <ShowDialog open={open} onClose={()=>{ setOpen(false); setEditing(null); }} initial={editing || undefined} onSave={handleSave} />
    </Stack>
  );
}

function ShowDialog({ open, onClose, initial, onSave }: { open: boolean; onClose: ()=>void; initial?: Partial<ShowItem>; onSave: (p: any)=>void; }) {
  const [slug, setSlug] = useState(initial?.slug || '');
  const [title, setTitle] = useState(initial?.title || '');
  // Channel id_slug stored as string in state for Select; sent directly to backend
  const [channel, setChannel] = useState<string>('');
  const [isActive, setIsActive] = useState(!!initial?.is_active);
  const [synopsis, setSynopsis] = useState('');
  const [locale, setLocale] = useState('am');
  const [tagsInput, setTagsInput] = useState('');
  const [allCategories, setAllCategories] = useState<CategoryItem[]>([]);
  const [selectedCategorySlugs, setSelectedCategorySlugs] = useState<string[]>([]);
  const [channels, setChannels] = useState<ChannelOption[]>([]);
  const [slugTouched, setSlugTouched] = useState(!!initial?.slug);

  useEffect(()=>{
    // When dialog is (re)opened, initialize fields from initial or clear for Add mode
    if (!open) return;
    setSlug(initial?.slug || '');
    setTitle(initial?.title || '');
    // In Add mode, ensure channel starts empty string (never undefined)
    if (initial && typeof initial.channel === 'string') {
      setChannel(initial.channel);
    } else {
      setChannel('');
    }
    setIsActive(!!initial?.is_active);
    setSynopsis('');
    setLocale('am');
    setTagsInput('');
    // Pre-populate selected categories when editing an existing show
    if (initial && Array.isArray((initial as any).categories)) {
      const slugs = ((initial as any).categories as { slug: string }[])
        .map(c => c.slug)
        .filter(Boolean);
      setSelectedCategorySlugs(slugs);
    } else {
      setSelectedCategorySlugs([]);
    }
    setSlugTouched(!!initial?.slug);
  }, [open, initial]);

  useEffect(() => {
    if (!open) return;
    (async () => {
      try {
        const [chanRes, catRes] = await Promise.all([
          api.get('/channels/', { params: { page_size: 500 } }),
          api.get('/series/categories/', { params: { page_size: 500 } }),
        ]);
        const chanList = Array.isArray(chanRes.data?.results) ? chanRes.data.results : (Array.isArray(chanRes.data) ? chanRes.data : []);
        // Debug: inspect raw channel objects used for the Select in Add Show dialog
        // Remove or comment out once you're satisfied with the mapping.
        // eslint-disable-next-line no-console
        //console.log('ShowDialog channels:', chanList);
        setChannels(chanList.map((c: any) => ({
          // use id_slug as value for the Select; backend will accept this
          id: c.id_slug,
          // Prefer English name; fall back to other fields so it's never undefined
          name: c.name_en || c.title || c.name || c.id_slug || c.slug || String(c.id),
          slug: c.id_slug || c.slug,
          is_active: !!c.is_active,
        })));
        const catList = Array.isArray(catRes.data?.results) ? catRes.data.results : (Array.isArray(catRes.data) ? catRes.data : []);
        setAllCategories(catList);
      } catch (e) {
        // ignore loading errors here; parent will show errors on list fetch
      }
    })();
  }, [open]);

  // Auto-generate slug from title when user hasn't manually edited slug
  useEffect(() => {
    if (!open) return;
    if (slugTouched) return;
    let auto = title
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9\s-]/g, '')
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-');
    // If the title contains only non-ASCII characters (e.g. Amharic), the above may yield an empty slug.
    // In that case, fall back to a safe ASCII slug based on a timestamp.
    if (!auto) {
      auto = `show-${Date.now()}`;
    }
    setSlug(auto);
  }, [title, open, slugTouched]);

  const submit = () => {
    const channelSlug = channel && channel !== 'undefined' ? channel : '';
    if (!slug.trim() || !title.trim() || !channelSlug) {
      alert('Slug, title and channel are required');
      return;
    }
    const tags = tagsInput
      .split(',')
      .map(t => t.trim())
      .filter(Boolean);
    const payload = {
      slug: slug.trim(),
      title: title.trim(),
      // Backend expects channel by id_slug
      channel: channelSlug,
      is_active: isActive,
      synopsis: synopsis.trim() || '',
      default_locale: locale || 'am',
      tags,
      category_slugs: selectedCategorySlugs,
    };
    // Debug: inspect payload before sending
    // eslint-disable-next-line no-console
    //console.log('ShowDialog submit payload:', payload, 'raw channel state:', channel);
    onSave(payload);
  };

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>{initial?.slug ? 'Edit Show' : 'Add Show'}</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt:1 }}>
          <TextField
            label="Slug (auto-generated)"
            value={slug}
            disabled
            helperText="Slug is generated automatically from the title/channel and cannot be edited."
          />
          <TextField label="Title" value={title} onChange={e=>setTitle(e.target.value)} />
          <Select
            displayEmpty
            value={channel}
            onChange={e=>{
              const v = (e.target.value ?? '') as string;
              setChannel(v || '');
            }}
            fullWidth
            renderValue={(value) => {
              if (!value) return 'Select channel…';
              const c = channels.find(ch => ch.id === value);
              if (!c) return 'Select channel…';
              return `${c.name}${c.is_active ? '' : ' (inactive)'}`;
            }}
          >
            {channels.length === 0 ? (
              <MenuItem key="channel-none" value="" disabled>
                No channels found for this tenant. Create a channel first.
              </MenuItem>
            ) : (
              channels.map((c, idx) => {
                const label = (c.name ?? (c as any).title ?? c.slug ?? (c as any).id_slug ?? `Channel ${c.id}`);
                return (
                  <MenuItem key={`ch-${idx}`} value={c.id}>
                    {label}{c.is_active ? '' : ' (inactive)'}
                  </MenuItem>
                );
              })
            )}
          </Select>
          <FormControlLabel control={<Switch checked={isActive} onChange={e=>setIsActive(e.target.checked)} />} label="Active" />
          <TextField label="Synopsis" value={synopsis} onChange={e=>setSynopsis(e.target.value)} multiline minRows={3} />
          <TextField label="Default locale" value={locale} onChange={e=>setLocale(e.target.value)} />
          <TextField label="Tags (comma separated)" value={tagsInput} onChange={e=>setTagsInput(e.target.value)} />
          <Box>
            <Typography variant="subtitle2" gutterBottom>Categories</Typography>
            <Select
              multiple
              value={selectedCategorySlugs}
              onChange={e=>{
                const val = e.target.value;
                setSelectedCategorySlugs(Array.isArray(val) ? val as string[] : []);
              }}
              fullWidth
              renderValue={(selected) => {
                const names = allCategories.filter(c => selected.includes(c.slug)).map(c => c.name);
                return names.join(', ');
              }}
            >
              {allCategories.map((cat, idx) => (
                <MenuItem key={`cat-${idx}`} value={cat.slug}>
                  {cat.name}
                </MenuItem>
              ))}
            </Select>
          </Box>
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
  const [syncMessage, setSyncMessage] = useState<string | null>(null);
  const [expandedSeasonIds, setExpandedSeasonIds] = useState<Record<number, boolean>>({});
  const [seasonEpisodes, setSeasonEpisodes] = useState<Record<number, EpisodeItem[]>>({});
  const [epDialogOpen, setEpDialogOpen] = useState(false);
  const [epEditing, setEpEditing] = useState<EpisodeItem | null>(null);

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

  const handleSync = async (season: SeasonItem) => {
    if (!window.confirm('Run sync now for this Season (fetch episodes)?')) return;
    try {
      const res = await api.post(`/series/seasons/${season.id}/sync-now/`);
      const data = res?.data || {};
      // eslint-disable-next-line no-console
      //console.log('Season sync-now result:', data);
      const msg: string = data.detail || 'Sync complete.';
      setSyncMessage(msg);
    } catch (e:any) {
      onError(e?.response?.data?.detail || 'Failed to sync Season');
    }
  };

  const toggleSeasonExpanded = async (season: SeasonItem) => {
    const currentlyOpen = !!expandedSeasonIds[season.id];
    if (currentlyOpen) {
      setExpandedSeasonIds(prev => ({ ...prev, [season.id]: false }));
      return;
    }
    setExpandedSeasonIds(prev => ({ ...prev, [season.id]: true }));
    // Lazy-load episodes for this season if not already fetched
    if (!seasonEpisodes[season.id]) {
      try {
        const { data } = await api.get('/series/episodes/', {
          params: { season: season.id, page_size: EPISODES_PAGE_SIZE, ordering: 'episode_number' },
        });
        const list = Array.isArray(data) ? data : (data?.results || []);
        setSeasonEpisodes(prev => ({ ...prev, [season.id]: list }));
      } catch (e:any) {
        onError(e?.response?.data?.detail || 'Failed to load Episodes for season');
      }
    }
  };

  const openEpisodeDialog = (ep: EpisodeItem) => {
    setEpEditing(ep);
    setEpDialogOpen(true);
  };

  const handleEpisodeSave = async (payload: Partial<EpisodeItem>) => {
    try {
      if (!epEditing?.id) {
        onError('Creating new Episodes from the Seasons tab is disabled.');
        return;
      }
      await api.patch(`/series/episodes/${epEditing.id}/`, payload);
      setEpDialogOpen(false);
      const seasonId = epEditing.season;
      // Refresh just this season's episodes list
      try {
        const { data } = await api.get('/series/episodes/', {
          params: { season: seasonId, page_size: EPISODES_PAGE_SIZE, ordering: 'episode_number' },
        });
        const list = Array.isArray(data) ? data : (data?.results || []);
        setSeasonEpisodes(prev => ({ ...prev, [seasonId]: list }));
      } catch (e:any) {
        onError(e?.response?.data?.detail || 'Failed to refresh Episodes for season');
      }
    } catch (e:any) {
      onError(e?.response?.data?.detail || 'Failed to save Episode');
    }
  };

  const handleEpisodeDelete = async (ep: EpisodeItem) => {
    if (!window.confirm('Delete this Episode?')) return;
    try {
      await api.delete(`/series/episodes/${ep.id}/`);
      const seasonId = ep.season;
      setSeasonEpisodes(prev => ({
        ...prev,
        [seasonId]: (prev[seasonId] || []).filter(e => e.id !== ep.id),
      }));
    } catch (e:any) {
      onError(e?.response?.data?.detail || 'Failed to delete Episode');
    }
  };

  return (
    <Stack spacing={2}>
      <Stack direction="row" alignItems="center" spacing={1} sx={{ flexWrap:'wrap', rowGap:1 }}>
        <TextField size="small" label="Search by season or show title" value={search} onChange={e=>setSearch(e.target.value)} onKeyDown={(e)=>{ if (e.key==='Enter') { setPage(1); load(); } }} />
        <Box sx={{ flexGrow: 1 }} />
        {isStaff && <Button startIcon={<AddIcon />} variant="contained" onClick={()=>{ setEditing(null); setOpen(true); }}>Add Season</Button>}
        <Tooltip title="Reload"><span><IconButton onClick={load} disabled={loading}><RefreshIcon/></IconButton></span></Tooltip>
      </Stack>
      <Stack spacing={1}>
        {items.map(it => (
          <Box key={it.id} sx={{ p:1, border:'1px solid', borderColor:'divider', borderRadius:1, minWidth:0 }}>
            <Stack direction="row" spacing={2} alignItems="center">
              <Box sx={{ flex: 1, minWidth:0 }}>
                <Typography
                  variant="subtitle1"
                  noWrap
                  title={`${it.show_title || it.show} • S${it.number}${it.title ? ' • ' + it.title : ''}`}
                >
                  {(it.show_title || it.show)} • S{it.number}{it.title ? ` • ${it.title}` : ''}
                </Typography>
                {it.yt_playlist_id && (
                  <Typography
                    variant="caption"
                    color="text.secondary"
                    noWrap
                    title={it.yt_playlist_id}
                    sx={{ fontFamily:'monospace' }}
                  >
                    {it.yt_playlist_id}
                  </Typography>
                )}
              </Box>
              <Chip size="small" color={it.is_enabled ? 'success':'default'} label={it.is_enabled ? 'Enabled':'Disabled'} />
              {isStaff && (
                <Stack direction="row" spacing={1}>
                  <Tooltip title="Sync episodes for this Season's channel">
                    <span>
                      <IconButton onClick={()=>handleSync(it)} disabled={loading}>
                        <RefreshIcon />
                      </IconButton>
                    </span>
                  </Tooltip>
                  <IconButton onClick={()=>{ setEditing(it); setOpen(true); }}><EditIcon/></IconButton>
                  <IconButton onClick={()=>handleDelete(it.id)} color="error"><DeleteIcon/></IconButton>
                  <Button size="small" onClick={()=>toggleSeasonExpanded(it)}>
                    {expandedSeasonIds[it.id] ? 'Hide episodes' : 'Show episodes'}
                  </Button>
                </Stack>
              )}
            </Stack>
            <Collapse in={!!expandedSeasonIds[it.id]} timeout="auto" unmountOnExit>
              <Stack spacing={0.5} sx={{ mt:1, ml:2 }}>
                {(seasonEpisodes[it.id] || []).map(ep => (
                  <Stack key={ep.id} direction="row" spacing={2} alignItems="center" sx={{ p:0.5, border:'1px solid', borderColor:'divider', borderRadius:1, minWidth:0 }}>
                    <Box sx={{ flex: 1, minWidth:0 }}>
                      <Typography variant="body2" noWrap title={ep.title}>{ep.title}</Typography>
                      <Typography variant="caption" color="text.secondary" noWrap title={ep.source_video_id} sx={{ fontFamily:'monospace' }}>{ep.source_video_id}</Typography>
                    </Box>
                    <Chip size="small" color={ep.visible ? 'success':'default'} label={ep.visible ? 'Visible':'Hidden'} />
                    <Chip size="small" label={ep.status} />
                    <Stack direction="row" spacing={1}>
                      <IconButton onClick={()=>openEpisodeDialog(ep)}><EditIcon/></IconButton>
                      <IconButton onClick={()=>handleEpisodeDelete(ep)} color="error"><DeleteIcon/></IconButton>
                    </Stack>
                  </Stack>
                ))}
                {(!seasonEpisodes[it.id] || seasonEpisodes[it.id].length === 0) && (
                  <Typography variant="caption" color="text.secondary">No episodes yet for this season.</Typography>
                )}
              </Stack>
            </Collapse>
          </Box>
        ))}
      </Stack>
      <Snackbar open={!!syncMessage} autoHideDuration={4000} onClose={()=>setSyncMessage(null)}>
        <Alert severity="success" variant="filled" onClose={()=>setSyncMessage(null)} sx={{ width:'100%' }}>
          {syncMessage}
        </Alert>
      </Snackbar>
      <Box sx={{ display:'flex', justifyContent:'center' }}>
        <Pagination page={page} onChange={(_,p)=>setPage(p)} count={Math.max(1, Math.ceil(count / 24))} color="primary" />
      </Box>
      <SeasonDialog open={open} onClose={()=>{ setOpen(false); setEditing(null); }} initial={editing || undefined} onSave={handleSave} />
      <EpisodeDialog open={epDialogOpen} onClose={()=>{ setEpDialogOpen(false); setEpEditing(null); }} initial={epEditing || undefined} onSave={handleEpisodeSave} />
    </Stack>
  );
}

function SeasonDialog({ open, onClose, initial, onSave }: { open: boolean; onClose: ()=>void; initial?: Partial<SeasonItem>; onSave: (p: Partial<SeasonItem>)=>void; }) {
  const [show, setShow] = useState(initial?.show || '');
  const [number, setNumber] = useState<number | ''>(initial?.number ?? '');
  const [title, setTitle] = useState(initial?.title || '');
  const [playlist, setPlaylist] = useState(initial?.yt_playlist_id || '');
  const [coverImage, setCoverImage] = useState(initial?.cover_image || '');
  const [enabled, setEnabled] = useState(!!initial?.is_enabled);
  const [showChoices, setShowChoices] = useState<ShowChoice[]>([]);
  const [playlistChoices, setPlaylistChoices] = useState<PlaylistChoice[]>([]);

  useEffect(()=>{
    setShow(initial?.show || '');
    setNumber(initial?.number ?? '');
    setTitle(initial?.title || '');
    setPlaylist(initial?.yt_playlist_id || '');
    setCoverImage(initial?.cover_image || '');
    setEnabled(!!initial?.is_enabled);
  }, [initial]);

  useEffect(() => {
    if (!open) return;
    (async () => {
      try {
        const { data } = await api.get('/series/shows/', { params: { page_size: 500, ordering: 'title' } });
        const list = Array.isArray(data) ? data : (data?.results || []);
        const mapped: ShowChoice[] = list
          .filter((s: any) => s && s.slug)
          .map((s: any) => ({
            slug: s.slug,
            title: s.title || s.slug,
            // ShowSerializer.channel now returns channel id_slug (string)
            channel: typeof (s as any).channel === 'string' ? (s as any).channel : undefined,
          }));
        setShowChoices(mapped);
      } catch {
        // ignore; user can still type slug manually if needed
      }
    })();
  }, [open]);

  // When user changes Show in Add mode, clear playlist + detected playlists so they refresh for the new show
  useEffect(() => {
    if (!open) return;
    if (initial?.id) return; // editing existing Season - keep its playlist
    setPlaylist('');
    setPlaylistChoices([]);
  }, [open, show, initial]);

  // Auto-detect playlist for selected show/channel when opening the dialog or changing show
  useEffect(() => {
    if (!open) return;
    if (playlist.trim()) return; // don't override if user already typed one
    const choice = showChoices.find(sc => sc.slug === show);
    if (!choice?.channel) return;
    (async () => {
      try {
        const { data } = await api.get('/channels/playlists/', {
          params: {
            channel: choice.channel,
            is_active: 'true',
            ordering: '-yt_last_item_published_at',
            page_size: 20,
          },
        });
        const list = Array.isArray(data) ? data : (data?.results || []);
        const mapped: PlaylistChoice[] = list
          .filter((pl: any) => pl && typeof pl.id === 'string')
          .map((pl: any) => ({ id: pl.id, title: pl.title || pl.id }));
        setPlaylistChoices(mapped);
        if (mapped.length > 0 && !playlist.trim()) {
          // Default to the first playlist but still show all options
          setPlaylist(mapped[0].id);
        }
      } catch {
        // if detection fails, user can enter the playlist manually
      }
    })();
  }, [open, show, showChoices]);

  const submit = () => {
    if (!show.trim() || number === '') { alert('Show slug and number are required'); return; }
    onSave({
      show: show.trim(),
      number: typeof number==='number' ? number : Number(number),
      title: title.trim() || undefined,
      yt_playlist_id: playlist.trim() || undefined,
      cover_image: coverImage.trim() || undefined,
      is_enabled: enabled,
    });
  };

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>{initial?.id ? 'Edit Season' : 'Add Season'}</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt:1 }}>
          <Select
            fullWidth
            displayEmpty
            value={show}
            onChange={e=>setShow(String(e.target.value || ''))}
            renderValue={(value) => {
              if (!value) return 'Select show…';
              const s = showChoices.find(sc => sc.slug === value);
              return s ? `${s.title} (${s.slug})` : String(value);
            }}
          >
            {showChoices.length === 0 ? (
              <MenuItem value="" disabled>
                No shows loaded – type slug manually in Number field helper if needed.
              </MenuItem>
            ) : (
              showChoices.map((s, idx) => (
                <MenuItem key={`show-${idx}`} value={s.slug}>
                  {s.title} ({s.slug})
                </MenuItem>
              ))
            )}
          </Select>
          <TextField
            label="Number"
            type="number"
            value={number}
            onChange={e=>setNumber(e.target.value===''? '': Number(e.target.value))}
          />
          <TextField
            label="Title"
            value={title}
            onChange={e=>setTitle(e.target.value)}
          />
          <TextField
            label="Cover image path"
            helperText="Relative path or URL to the Season cover image."
            value={coverImage}
            onChange={e=>setCoverImage(e.target.value)}
          />
          <TextField
            label="YouTube Playlist ID"
            helperText={playlistChoices.length
              ? 'Select a playlist for this show/channel. You can still edit the PL... id manually.'
              : 'Playlist ID (PL...). Enter manually if no active playlists are detected for the selected channel.'}
            value={playlist}
            onChange={e=>setPlaylist(e.target.value)}
          />
          {playlistChoices.length > 0 && (
            <Select
              fullWidth
              value={playlist || ''}
              displayEmpty
              onChange={e=>setPlaylist(String(e.target.value || ''))}
              renderValue={(value) => {
                if (!value) return 'Select playlist…';
                const pl = playlistChoices.find(p => p.id === value);
                return pl ? `${pl.title} (${pl.id})` : String(value);
              }}
            >
              {playlistChoices.map((pl, idx) => (
                <MenuItem key={`pl-${idx}`} value={pl.id}>
                  {pl.title} ({pl.id})
                </MenuItem>
              ))}
            </Select>
          )}
          <FormControlLabel control={<Switch checked={enabled} onChange={e=>setEnabled(e.target.checked)} />} label="Enabled" />
          {initial?.last_synced_at && (
            <Typography variant="caption" color="text.secondary">
              Last synced at: {initial.last_synced_at}
            </Typography>
          )}
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
  const [seasons, setSeasons] = useState<SeasonItem[]>([]);
  const [openShows, setOpenShows] = useState<Record<string, boolean>>({});
  const [openSeasons, setOpenSeasons] = useState<Record<string, boolean>>({});

  const load = async () => {
    setLoading(true);
    try {
      const params: any = { ordering: 'episode_number', page_size: EPISODES_PAGE_SIZE };
      if (search.trim()) params.search = search.trim();
      const { data } = await api.get('/series/episodes/', { params });
      const list = Array.isArray(data) ? data : (data?.results || []);
      setItems(list);
    } catch (e1:any) {
      try {
        const { data } = await api.get('/series/episodes/');
        const list = Array.isArray(data) ? data : (data?.results || []);
        setItems(list);
      } catch (e2:any) {
        onError(e2?.response?.data?.detail || e1?.response?.data?.detail || 'Failed to load Episodes');
      }
    } finally { setLoading(false); }
  };
  useEffect(()=>{ load(); }, []);

  useEffect(() => {
    // Load Seasons so we can map episode.season -> show slug and season number
    (async () => {
      try {
        const { data } = await api.get('/series/seasons/', { params: { page_size: 500, ordering: 'number' } });
        const list = Array.isArray(data) ? data : (data?.results || []);
        setSeasons(list);
      } catch {
        // ignore; grouping will fall back to using only season id
      }
    })();
  }, []);

  const seasonsById = useMemo(() => {
    const map: Record<number, SeasonItem> = {};
    seasons.forEach(s => { map[s.id] = s; });
    return map;
  }, [seasons]);

  const groupedByShow = useMemo(() => {
    const result: Record<string, { show: string; label: string; seasons: Record<number, { season: SeasonItem | null; episodes: EpisodeItem[] }> }> = {};
    items.forEach(ep => {
      const season = seasonsById[ep.season] || null;
      const showSlug = season?.show || 'unknown-show';
      const showLabel = season?.show_title || showSlug;
      if (!result[showSlug]) {
        result[showSlug] = { show: showSlug, label: showLabel, seasons: {} };
      }
      if (!result[showSlug].seasons[ep.season]) {
        result[showSlug].seasons[ep.season] = { season, episodes: [] };
      }
      result[showSlug].seasons[ep.season].episodes.push(ep);
    });
    return result;
  }, [items, seasonsById]);

  const toggleShow = (slug: string) => {
    setOpenShows(prev => ({ ...prev, [slug]: !prev[slug] }));
  };

  const toggleSeason = (showSlug: string, seasonId: number) => {
    const key = `${showSlug}:${seasonId}`;
    setOpenSeasons(prev => ({ ...prev, [key]: !prev[key] }));
  };

  const handleSave = async (payload: Partial<EpisodeItem>) => {
    try {
      // Only allow editing existing episodes from this UI; no creation of new episodes
      if (!editing?.id) {
        onError('Creating new Episodes from this page is disabled.');
        return;
      }
      await api.patch(`/series/episodes/${editing.id}/`, payload);
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
        <TextField size="small" label="Search by episode title or number" value={search} onChange={e=>setSearch(e.target.value)} onKeyDown={(e)=>{ if (e.key==='Enter') { load(); } }} />
        <Box sx={{ flexGrow: 1 }} />
        {/* Creating new Episodes from this UI is disabled; keep only edit/delete for existing ones. */}
        <Tooltip title="Reload"><span><IconButton onClick={load} disabled={loading}><RefreshIcon/></IconButton></span></Tooltip>
      </Stack>
      <Stack spacing={1}>
        {Object.keys(groupedByShow).sort().map(showSlug => {
          const group = groupedByShow[showSlug];
          const seasonsArr = Object.values(group.seasons).sort((a, b) => {
            const an = a.season?.number ?? 0;
            const bn = b.season?.number ?? 0;
            return an - bn;
          });
          return (
            <Box key={showSlug} sx={{ border:'1px solid', borderColor:'divider', borderRadius:1, p:1 }}>
              <Stack direction="row" alignItems="center" spacing={1} sx={{ cursor:'pointer' }} onClick={() => toggleShow(showSlug)}>
                <Typography variant="subtitle1" sx={{ flex:1 }}>{group.label}</Typography>
                <Typography variant="caption" color="text.secondary">
                  {openShows[showSlug] ? 'Hide seasons' : 'Show seasons'}
                </Typography>
              </Stack>
              <Collapse in={!!openShows[showSlug]} timeout="auto" unmountOnExit>
                <Stack spacing={1} sx={{ mt:1 }}>
                  {seasonsArr.map(({ season, episodes }) => {
                    const sid = season?.id || episodes[0]?.season;
                    const key = `${showSlug}:${sid}`;
                    return (
                      <Box key={sid} sx={{ ml:1 }}>
                        <Stack direction="row" alignItems="center" spacing={1} sx={{ cursor:'pointer' }} onClick={() => toggleSeason(showSlug, sid)}>
                          <Typography variant="subtitle2" sx={{ flex:1 }}>
                            Season {season?.number ?? episodes[0]?.season}{season?.title ? ` – ${season.title}` : ''}
                          </Typography>
                          <Typography variant="caption" color="text.secondary">
                            {openSeasons[key] ? 'Hide episodes' : 'Show episodes'}
                          </Typography>
                        </Stack>
                        <Collapse in={!!openSeasons[key]} timeout="auto" unmountOnExit>
                          <Stack spacing={0.5} sx={{ mt:0.5 }}>
                            {episodes.map(it => (
                              <Stack key={it.id} direction="row" spacing={2} alignItems="center" sx={{ p:0.5, border:'1px solid', borderColor:'divider', borderRadius:1, minWidth:0 }}>
                                <Box sx={{ flex: 1, minWidth:0 }}>
                                  <Typography variant="body2" noWrap title={it.title}>{it.title}</Typography>
                                  <Typography variant="caption" color="text.secondary" noWrap title={it.source_video_id} sx={{ fontFamily:'monospace' }}>{it.source_video_id}</Typography>
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
                        </Collapse>
                      </Box>
                    );
                  })}
                </Stack>
              </Collapse>
            </Box>
          );
        })}
      </Stack>
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
