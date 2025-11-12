import React, { useEffect, useState } from 'react';
import { Box, Button, Card, CardContent, IconButton, List, ListItem, ListItemText, Stack, Typography } from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';
import api from '../services/api';

interface NotificationItem {
  id: number;
  title: string;
  body: string;
  data: any;
  created_at: string;
  read_at: string | null;
}

const UserNotifications: React.FC = () => {
  const [items, setItems] = useState<NotificationItem[]>([]);
  const [loading, setLoading] = useState(false);

  const load = async () => {
    setLoading(true);
    try {
      const { data } = await api.get('/channels/notifications/', { params: { page_size: 100 } });
      setItems((data?.results || []) as NotificationItem[]);
    } catch {
      setItems([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(()=>{ load(); }, []);

  const markAllRead = async () => {
    try {
      await api.post('/channels/notifications/mark-all-read/');
      await load();
    } catch {}
  };

  return (
    <Stack spacing={2}>
      <Stack direction="row" spacing={2} alignItems="center">
        <Typography variant="h5">My Notifications</Typography>
        <IconButton onClick={load} disabled={loading}><RefreshIcon/></IconButton>
        <Button variant="outlined" onClick={markAllRead}>Mark all read</Button>
      </Stack>
      <Card>
        <CardContent>
          <List>
            {items.map(n => (
              <ListItem key={n.id} divider>
                <ListItemText
                  primary={<Box sx={{ display:'flex', alignItems:'center', gap:1 }}>
                    <Typography variant="subtitle1">{n.title || '(no title)'}</Typography>
                    {n.read_at ? (
                      <Typography variant="caption" color="text.secondary">read</Typography>
                    ) : (
                      <Typography variant="caption" color="warning.main">unread</Typography>
                    )}
                  </Box>}
                  secondary={<>
                    <Typography variant="body2">{n.body}</Typography>
                    <Box component="pre" sx={{ mt:1, p:1, bgcolor:'action.hover', borderRadius:1, fontSize:12 }}>
                      {JSON.stringify(n.data || {}, null, 2)}
                    </Box>
                    <Typography variant="caption" color="text.secondary">{new Date(n.created_at).toLocaleString()}</Typography>
                  </>}
                />
              </ListItem>
            ))}
          </List>
        </CardContent>
      </Card>
    </Stack>
  );
};

export default UserNotifications;
