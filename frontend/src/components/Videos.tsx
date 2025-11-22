import React, { useEffect, useState } from 'react';
import { Box, Card, CardContent, Grid, Stack, TextField, Typography, IconButton, Tooltip, Chip, Pagination } from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';
import api from '../services/api';

interface VideoItem {
  id: number;
  channel: string;
  playlist: string;
  video_id: string;
  title: string;
  thumbnails?: any;
  published_at?: string | null;
  is_active: boolean;
}

const VIDEOS_PAGE_SIZE = 24;

const Videos: React.FC = () => {
  const [items, setItems] = useState<VideoItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [channel, setChannel] = useState('');
  const [playlist, setPlaylist] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [count, setCount] = useState(0);

  const load = async () => {
    setLoading(true);
    try {
      const params: any = { page, page_size: VIDEOS_PAGE_SIZE };
      if (channel.trim()) params.channel = channel.trim();
      if (playlist.trim()) params.playlist = playlist.trim();
      if (search.trim()) params.search = search.trim();
      const { data } = await api.get('/channels/videos/', { params });
      const list = Array.isArray(data) ? data : (data?.results || []);
      setItems(list);
      setCount(typeof (data as any)?.count === 'number' ? (data as any).count : list.length);
    } catch {
      setItems([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(()=>{ load(); }, [page]);

  const thumbUrl = (t:any): string | null => {
    if (!t || typeof t !== 'object') return null;
    for (const k of ['maxres','standard','high','medium','default']) {
      const v = t?.[k];
      if (v && typeof v.url === 'string') return v.url;
    }
    if (typeof t.url === 'string') return t.url;
    return null;
  };

  return (
    <Stack spacing={2}>
      <Stack direction="row" spacing={2} alignItems="center" sx={{ flexWrap: 'wrap', rowGap: 1 }}>
        <Typography variant="h5">Videos</Typography>
        <TextField size="small" label="Search title or channel name" value={search} onChange={e=>setSearch(e.target.value)} onKeyDown={(e)=>{ if (e.key==='Enter') { setPage(1); load(); } }} />
        <TextField size="small" label="Filter by channel slug" value={channel} onChange={e=>setChannel(e.target.value)} onKeyDown={(e)=>{ if (e.key==='Enter') { setPage(1); load(); } }} />
        <TextField size="small" label="Filter by playlist id" value={playlist} onChange={e=>setPlaylist(e.target.value)} onKeyDown={(e)=>{ if (e.key==='Enter') { setPage(1); load(); } }} />
        <Tooltip title="Reload"><span><IconButton onClick={load} disabled={loading}><RefreshIcon/></IconButton></span></Tooltip>
      </Stack>
      <Grid container spacing={2}>
        {items.map(v => {
          const tu = thumbUrl((v as any).thumbnails);
          return (
            <Grid item xs={12} sm={6} md={4} lg={3} key={v.id}>
              <Card>
                <Box
                  sx={{ height: 140, display:'flex', alignItems:'center', justifyContent:'center', bgcolor:'action.hover' }}
                  component="a"
                  href={v.video_id ? `https://www.youtube.com/watch?v=${encodeURIComponent(v.video_id)}` : undefined}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {tu && <img src={tu} alt="thumb" style={{ maxHeight: 120, maxWidth:'90%', objectFit:'cover' }} />}
                </Box>
                <CardContent>
                  <Typography
                    variant="subtitle1"
                    title={v.title || v.video_id}
                    sx={{
                      wordBreak: 'break-word',
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      display: '-webkit-box',
                      WebkitLineClamp: 2,
                      WebkitBoxOrient: 'vertical',
                    }}
                  >
                    {v.title || v.video_id}
                  </Typography>
                  <Typography variant="caption" color="text.secondary">{v.channel} · PL {v.playlist}</Typography>
                  <Box sx={{ mt: 1 }}>
                    <Chip size="small" color={v.is_active ? 'success' : 'default'} label={v.is_active ? 'Active' : 'Inactive'} />
                  </Box>
                </CardContent>
              </Card>
            </Grid>
          );
        })}
      </Grid>
      <Box sx={{ display:'flex', justifyContent:'center' }}>
        <Pagination
          page={page}
          onChange={(_, p) => setPage(p)}
          count={Math.max(1, Math.ceil(count / VIDEOS_PAGE_SIZE))}
          color="primary"
        />
      </Box>
    </Stack>
  );
};

export default Videos;
