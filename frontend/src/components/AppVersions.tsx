import React, { useEffect, useState } from 'react';
import { Box, Card, CardContent, Typography, Stack, TextField, Button, MenuItem } from '@mui/material';
import api from '../services/api';

const AppVersions: React.FC = () => {
  const [platform, setPlatform] = useState('web');
  const [version, setVersion] = useState('1.0.0');
  const [latest, setLatest] = useState<any>(null);
  const [supported, setSupported] = useState<any>(null);
  const [check, setCheck] = useState<any>(null);

  const load = async () => {
    try {
      const [lat, sup] = await Promise.all([
        api.get('/channels/version/latest/', { params: { platform } }).catch(()=>({data:null})),
        api.get('/channels/version/supported/', { params: { platform } }).catch(()=>({data:null})),
      ]);
      setLatest(lat.data);
      setSupported(sup.data);
    } catch {}
  };

  useEffect(()=>{ load(); }, [platform]);

  const doCheck = async () => {
    try {
      const { data } = await api.post('/channels/version/check/', { platform, version });
      setCheck(data);
    } catch (e:any) {
      setCheck({ error: e?.response?.data || 'failed' });
    }
  };

  return (
    <Stack spacing={2}>
      <Card>
        <CardContent>
          <Typography variant="h6">Version Check</Typography>
          <Stack direction="row" spacing={2} sx={{ mt: 2 }}>
            <TextField
              select
              size="small"
              label="Platform"
              value={platform}
              onChange={e => setPlatform(e.target.value)}
              sx={{ minWidth: 140 }}
            >
              <MenuItem value="web">web</MenuItem>
              <MenuItem value="android">android</MenuItem>
              <MenuItem value="ios">ios</MenuItem>
            </TextField>
            <TextField size="small" label="Version" value={version} onChange={e=>setVersion(e.target.value)} />
            <Button variant="contained" onClick={doCheck}>Check</Button>
          </Stack>
          <Box component="pre" sx={{ mt: 2, p:1, bgcolor:'action.hover', borderRadius:1, fontSize:12 }}>
            {JSON.stringify(check, null, 2)}
          </Box>
        </CardContent>
      </Card>
      <Card>
        <CardContent>
          <Typography variant="h6">Latest</Typography>
          <Box component="pre" sx={{ mt: 2, p:1, bgcolor:'action.hover', borderRadius:1, fontSize:12 }}>
            {JSON.stringify(latest, null, 2)}
          </Box>
        </CardContent>
      </Card>
      <Card>
        <CardContent>
          <Typography variant="h6">Supported</Typography>
          <Box component="pre" sx={{ mt: 2, p:1, bgcolor:'action.hover', borderRadius:1, fontSize:12 }}>
            {JSON.stringify(supported, null, 2)}
          </Box>
        </CardContent>
      </Card>
    </Stack>
  );
};

export default AppVersions;
