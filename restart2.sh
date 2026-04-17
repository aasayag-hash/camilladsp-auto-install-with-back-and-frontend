fuser -k 5000/tcp 2>/dev/null
sleep 2
rm -rf /root/camilladsp/web/__pycache__
nohup python3 /root/camilladsp/web/server.py > /var/log/cdsp.log 2>&1 &
disown
sleep 3
echo "=== Server started ==="
curl -s http://127.0.0.1:5000/api/alsa-hw-capture
echo ""
curl -s http://127.0.0.1:5000/api/alsa-hw-playback