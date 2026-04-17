kill $(ps aux | grep 'python3.*server' | grep -v grep | awk '{print $2}') 2>/dev/null
sleep 2
rm -rf /root/camilladsp/web/__pycache__
nohup python3 /root/camilladsp/web/server.py > /var/log/cdsp.log 2>&1 &
disown
sleep 3
echo "=== capture ==="
curl -s http://127.0.0.1:5000/api/alsa-hw-capture
echo ""
echo "=== playback ==="
curl -s http://127.0.0.1:5000/api/alsa-hw-playback