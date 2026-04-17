kill -9 $(ps aux | grep 'python3.*server.py' | grep -v grep | awk '{print $2}')
sleep 2
nohup python3 /root/camilladsp/web/server.py > /var/log/cdsp.log 2>&1 &
disown
sleep 3
curl -s http://127.0.0.1:5000/api/capturedevices