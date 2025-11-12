import React, { useEffect, useState } from 'react';
import { Box, Card, CardContent, Chip, Grid, Stack, TextField, Typography, IconButton, Tooltip } from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';
import api from '../services/api';

interface PlaylistItem {
  id: string;
  channel: string; // channel slug
  title: string;
  item_count: number;
  is_active: boolean;
  channel_logo_url?: string;
  thumbnail_url?: string | null;
}

const Playlists: React.FC = () => {
  const [items, setItems] = useState<PlaylistItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [channel, setChannel] = useState('');

  const load = async () => {
    setLoading(true);
    try {
      const params: any = {};
      if (channel.trim()) params.channel = channel.trim();
      const { data } = await api.get('/channels/playlists/', { params });
      const list = Array.isArray(data) ? data : (data?.results || []);
      setItems(list);
    } catch {
      setItems([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(()=>{ load(); }, []);

  return (
    <Stack spacing={2}>
      <Stack direction="row" spacing={2} alignItems="center">
        <Typography variant="h5">Playlists</Typography>
        <TextField size="small" label="Filter by channel slug" value={channel} onChange={e=>setChannel(e.target.value)} onKeyDown={(e)=>{ if (e.key==='Enter') load(); }} />
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
                <Box sx={{ mt: 1 }}>
                  <Chip size="small" color={pl.is_active ? 'success' : 'default'} label={pl.is_active ? 'Active' : 'Inactive'} />
                </Box>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>
    </Stack>
  );
};

export default Playlists;
