kill -9 $(ps aux | grep 'server.py' | grep -v grep | awk '{print $2}') 2>/dev/null
sleep 2
rm -rf /root/camilladsp/web/__pycache__
nohup python3 /root/camilladsp/web/server.py > /var/log/cdsp.log 2>&1 &
disown
sleep 4
echo "=== hardware capture ==="
curl -s http://127.0.0.1:5000/api/alsa-hw-capture
echo ""
echo "=== hardware playback ==="
curl -s http://127.0.0.1:5000/api/alsa-hw-playback
echo ""
echo "=== log ==="
tail -5 /var/log/cdsp.log