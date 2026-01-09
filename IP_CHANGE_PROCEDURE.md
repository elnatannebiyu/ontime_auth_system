# IP Change Procedure - Admin Access Update

**When:** Your IP address changes and you can't access Django admin interface  
**Error:** "Access Denied - Your IP address (X.X.X.X) is not authorized"

---

## Quick Fix (5 Minutes)

### Step 1: SSH to Server
```bash
ssh root@75.119.138.31
# Enter password when prompted
```

### Step 2: Find Your Current IP
```bash
# Your IP is shown in the SSH connection
echo $SSH_CLIENT | awk '{print $1}'

# Or check what IP tried to access admin
sudo tail -20 /var/log/nginx/access.log | grep "secret-admin"
```

### Step 3: Edit Environment File
```bash
sudo nano /etc/ontime.env
```

Find this line:
```bash
ADMIN_ALLOWED_IPS=127.0.0.1,75.119.138.31,102.213.71.232
```

Add your new IP (comma-separated):
```bash
ADMIN_ALLOWED_IPS=127.0.0.1,75.119.138.31,102.213.71.232,YOUR_NEW_IP
```

Save and exit: `Ctrl+X`, then `Y`, then `Enter`

### Step 4: Restart Django
```bash
sudo systemctl restart ontime.service
sudo systemctl status ontime.service
```

Wait 3-5 seconds for workers to fully start.

### Step 5: Verify
```bash
# Check the service loaded the new IP
cat /proc/$(pgrep -f "gunicorn.*8001" | head -1)/environ | tr '\0' '\n' | grep ADMIN_ALLOWED_IPS
```

You should see your new IP in the list.

### Step 6: Test Admin Access
Open in browser:
```
https://api.aitechnologiesplc.com/secret-admin-56c244abb273f485/
```

You should now be able to access the admin interface.

---

## Alternative: Add IP Range Instead of Single IP

If your IP changes frequently, add a range:

```bash
# Edit /etc/ontime.env
sudo nano /etc/ontime.env

# Change to IP range (e.g., your ISP's subnet)
ADMIN_ALLOWED_IPS=127.0.0.1,75.119.138.31,102.213.0.0/16

# Restart
sudo systemctl restart ontime.service
```

**Note:** `/16` means all IPs from `102.213.0.0` to `102.213.255.255`

---

## Temporary: Disable IP Restriction (Not Recommended)

If you need emergency access and can't determine your IP:

```bash
# Edit /etc/ontime.env
sudo nano /etc/ontime.env

# Comment out the restriction (TEMPORARY ONLY)
# ADMIN_ALLOWED_IPS=127.0.0.1,75.119.138.31

# Or set to empty (allows all)
ADMIN_ALLOWED_IPS=

# Restart
sudo systemctl restart ontime.service
```

**⚠️ IMPORTANT:** Re-enable IP restriction after you're done!

---

## Check Current Allowed IPs

```bash
# View current configuration
cat /etc/ontime.env | grep ADMIN_ALLOWED_IPS

# View what the running service sees
cat /proc/$(pgrep -f "gunicorn.*8001" | head -1)/environ | tr '\0' '\n' | grep ADMIN_ALLOWED_IPS
```

---

## Troubleshooting

### Issue: Changes Not Taking Effect

**Solution:** Make sure you restarted the service:
```bash
sudo systemctl restart ontime.service
# NOT just reload - must be restart for env changes
```

### Issue: Can't Remember Admin URL

**Solution:** Check the environment file:
```bash
cat /etc/ontime.env | grep ADMIN_URL_PATH
```

Your admin URL is:
```
https://api.aitechnologiesplc.com/[ADMIN_URL_PATH]/
```

### Issue: Forgot Which IPs Are Allowed

**Solution:**
```bash
cat /etc/ontime.env | grep ADMIN_ALLOWED_IPS
```

### Issue: Service Won't Start After Edit

**Solution:** Check for syntax errors:
```bash
# View recent logs
sudo journalctl -u ontime.service -n 50 --no-pager

# Check if env file has syntax errors
cat /etc/ontime.env | grep -v "^#" | grep "="
```

Common mistakes:
- Missing quotes around values with spaces
- Typos in variable names
- Missing `=` sign

---

## Complete Checklist

- [ ] SSH to server
- [ ] Find your current IP
- [ ] Edit `/etc/ontime.env`
- [ ] Add new IP to `ADMIN_ALLOWED_IPS`
- [ ] Save file
- [ ] Restart service: `sudo systemctl restart ontime.service`
- [ ] Verify service is running: `sudo systemctl status ontime.service`
- [ ] Test admin access in browser

**Time required:** ~5 minutes

---

## Security Note

**Why IP allowlisting exists:**
- Audit finding #4 (Medium risk)
- Prevents unauthorized admin access
- Defense-in-depth security layer

**Best practice:**
- Use VPN with static IP for admin access
- Or use your office's static IP range
- Update allowlist when your IP changes

---

**Your current admin URL:** `https://api.aitechnologiesplc.com/secret-admin-56c244abb273f485/`  
**Save this URL securely!**
