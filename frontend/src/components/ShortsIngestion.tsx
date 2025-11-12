import React, { useEffect, useState } from 'react';
import { Box, Button, Card, CardContent, Stack, TextField, Typography, IconButton, Tooltip, List, ListItem, ListItemText } from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';
import api from '../services/api';

interface ShortJob {
  id: string;
  status: string;
  error_message?: string;
  hls_master_url?: string;
  updated_at?: string;
  created_at?: string;
}

const ShortsIngestion: React.FC = () => {
  const [url, setUrl] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [ready, setReady] = useState<ShortJob[]>([]);

  const loadReady = async () => {
    try {
      const { data } = await api.get('/channels/shorts/ready/', { params: { limit: 50 } });
      setReady(Array.isArray(data) ? data : []);
    } catch { setReady([]); }
  };

  useEffect(()=>{ loadReady(); }, []);

  const submit = async () => {
    if (!url.trim()) return; setSubmitting(true);
    try {
      await api.post('/channels/shorts/import/', { source_url: url.trim() });
      setUrl('');
      await loadReady();
    } catch {}
    finally { setSubmitting(false); }
  };

  return (
    <Stack spacing={2}>
      <Stack direction="row" spacing={2} alignItems="center">
        <Typography variant="h5">Short Ingestion Jobs</Typography>
        <Tooltip title="Reload READY list"><span><IconButton onClick={loadReady}><RefreshIcon/></IconButton></span></Tooltip>
      </Stack>
      <Card>
        <CardContent>
          <Typography variant="subtitle1">Submit a source URL</Typography>
          <Stack direction="row" spacing={2} sx={{ mt: 2 }}>
            <TextField fullWidth size="small" placeholder="https://youtube.com/... or other URL" value={url} onChange={e=>setUrl(e.target.value)} />
            <Button variant="contained" onClick={submit} disabled={submitting || !url.trim()}>Start</Button>
          </Stack>
        </CardContent>
      </Card>
      <Card>
        <CardContent>
          <Typography variant="subtitle1">READY items (latest)</Typography>
          <List>
            {ready.map(j => (
              <ListItem key={j.id} divider>
                <ListItemText
                  primary={<Typography variant="body1">{j.hls_master_url || j.id}</Typography>}
                  secondary={<Typography variant="caption" color="text.secondary">{j.status} · {j.updated_at || j.created_at || ''}</Typography>}
                />
              </ListItem>
            ))}
          </List>
        </CardContent>
      </Card>
    </Stack>
  );
};

export default ShortsIngestion;
