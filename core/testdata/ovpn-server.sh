#!/bin/sh
# A throwaway OpenVPN server for shikoo_ovpn_dll_windows_test.go, shaped like the shelf account: tcp, AES-256-CBC,
# auth SHA1, client certificate + password. Every run makes its own CA and certificates; nothing here is real.
set -e
PORT=${PORT:-11950}
cd /tmp
openssl ecparam -name prime256v1 -genkey -noout -out ca.key
openssl req -x509 -new -key ca.key -days 2 -subj /CN=test-ca -out ca.crt 2>/dev/null
for who in server client; do
  openssl ecparam -name prime256v1 -genkey -noout -out $who.key
  openssl req -new -key $who.key -subj /CN=test-$who -out $who.csr 2>/dev/null
  printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=%sAuth\n' $who > $who.ext
  openssl x509 -req -in $who.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 2 -extfile $who.ext -out $who.crt 2>/dev/null
done
printf '#!/bin/sh\n[ "$(sed -n 1p "$1")" = shikoo ] && [ "$(sed -n 2p "$1")" = test-pass ]\n' > check.sh
chmod +x check.sh
mkdir -p /dev/net; [ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200
{
  printf 'client\ndev tun\nproto tcp-client\nremote 127.0.0.1 %s\nnobind\ncipher AES-256-CBC\nauth SHA1\nauth-user-pass\n' "$PORT"
  printf '<ca>\n%s\n</ca>\n<cert>\n%s\n</cert>\n<key>\n%s\n</key>\n' "$(cat ca.crt)" "$(cat client.crt)" "$(cat client.key)"
} > /out/client.ovpn
cat > server.conf <<EOF
dev tun
proto tcp-server
port $PORT
server 10.89.0.0 255.255.255.0
topology subnet
ca /tmp/ca.crt
cert /tmp/server.crt
key /tmp/server.key
dh none
data-ciphers AES-256-CBC
auth SHA1
script-security 2
auth-user-pass-verify /tmp/check.sh via-file
tmp-dir /tmp
push "redirect-gateway def1"
push "dhcp-option DNS 1.1.1.1"
keepalive 10 60
verb 3
EOF
exec openvpn --config server.conf --log /out/server.log
