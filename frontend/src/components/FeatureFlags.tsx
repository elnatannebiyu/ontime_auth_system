import React, { useEffect, useState } from 'react';
import { Box, Card, CardContent, Typography, Stack, TextField } from '@mui/material';
import api from '../services/api';

const FeatureFlags: React.FC = () => {
  const [platform, setPlatform] = useState('web');
  const [version, setVersion] = useState('1.0.0');
  const [data, setData] = useState<any>(null);

  const load = async () => {
    try {
      const { data } = await api.get('/channels/features/', { params: { platform, version } });
      setData(data);
    } catch {
      setData(null);
    }
  };

  useEffect(()=>{ load(); }, [platform, version]);

  return (
    <Stack spacing={2}>
      <Card>
        <CardContent>
          <Typography variant="h6">Feature Flags</Typography>
          <Stack direction="row" spacing={2} sx={{ mt: 2 }}>
            <TextField size="small" label="Platform" value={platform} onChange={e=>setPlatform(e.target.value)} />
            <TextField size="small" label="Version" value={version} onChange={e=>setVersion(e.target.value)} />
          </Stack>
          <Box component="pre" sx={{ mt: 2, p:1, bgcolor:'action.hover', borderRadius:1, fontSize:12 }}>
            {JSON.stringify(data, null, 2)}
          </Box>
        </CardContent>
      </Card>
    </Stack>
  );
};

export default FeatureFlags;
