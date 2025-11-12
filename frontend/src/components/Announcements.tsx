import React, { useEffect, useState } from 'react';
import { Box, Card, CardContent, Stack, Typography, IconButton, Tooltip } from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';
import api from '../services/api';

const Announcements: React.FC = () => {
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(false);

  const load = async () => {
    setLoading(true);
    try {
      const { data } = await api.get('/channels/announcements/first-login/');
      setData(data);
    } catch {
      setData(null);
    } finally { setLoading(false); }
  };

  useEffect(()=>{ load(); }, []);

  return (
    <Stack spacing={2}>
      <Stack direction="row" spacing={2} alignItems="center">
        <Typography variant="h5">Announcements</Typography>
        <Tooltip title="Reload"><span><IconButton onClick={load} disabled={loading}><RefreshIcon/></IconButton></span></Tooltip>
      </Stack>
      <Card>
        <CardContent>
          {data ? (
            <>
              {data.title && <Typography variant="h6">{data.title}</Typography>}
              {data.body && <Typography variant="body1" sx={{ mt: 1, whiteSpace: 'pre-wrap' }}>{data.body}</Typography>}
            </>
          ) : (
            <Typography variant="body2" color="text.secondary">No first-login announcement.</Typography>
          )}
        </CardContent>
      </Card>
    </Stack>
  );
};

export default Announcements;
