"""Writes the sites an owner core keeps out of its tunnel first (core/shikoo_wg.go cutIran), and the foreign sites its
test keeps in. Run from Iran with no VPN: python tools/shikoo-iran-first.py
  tools/shikoo-iran-sites.txt    -> core/shikoo_iran_first.txt, answers of Iranian resolvers over plain UDP
  tools/shikoo-foreign-sites.txt -> core/testdata/shikoo_foreign_sites.txt, answers of 1.1.1.1 over DoH (HTTPS_PROXY
                                    is honoured), as a tunnel's DNS sees them
Writes nothing when fewer than 90% of the names answer: a broken network must not empty the list."""
import datetime, ipaddress, json, random, socket, struct, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IRAN_RESOLVERS = ['78.157.42.100', '178.22.122.100']  # Electro, Shecan


def names(path):
    for line in open(path, encoding='utf-8'):
        if line.strip() and not line.startswith('#'):
            category, host = line.split()
            yield category, host
            if host.count('.') == 1:
                yield category, 'www.' + host


def skip_name(r, i):
    while r[i]:
        if r[i] >= 0xC0:
            return i + 2
        i += r[i] + 1
    return i + 1


def udp_a(server, host):
    ident = random.getrandbits(16)
    query = struct.pack('>HHHHHH', ident, 0x0100, 1, 0, 0, 0)
    query += b''.join(bytes([len(p)]) + p.encode() for p in host.split('.')) + b'\0' + struct.pack('>HH', 1, 1)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.settimeout(4)
        for _ in range(2):
            try:
                s.sendto(query, (server, 53))
                r = s.recv(4096)
                break
            except OSError:
                continue
        else:
            return []
    if struct.unpack('>H', r[:2])[0] != ident or r[3] & 0x0F:
        return []
    i, out = skip_name(r, 12) + 4, []
    for _ in range(struct.unpack('>H', r[6:8])[0]):
        i = skip_name(r, i)
        kind, _, _, size = struct.unpack('>HHIH', r[i:i + 10])
        if kind == 1 and size == 4:
            out.append(socket.inet_ntoa(r[i + 10:i + 14]))
        i += 10 + size
    return out


def doh_a(host):
    req = urllib.request.Request(f'https://cloudflare-dns.com/dns-query?name={host}&type=A',
                                 headers={'accept': 'application/dns-json'})
    try:
        with urllib.request.urlopen(req, timeout=15) as f:
            return [a['data'] for a in json.load(f).get('Answer', []) if a['type'] == 1]
    except OSError:
        return []


def write(corpus, out, resolve, how):
    rows = list(names(ROOT / 'tools' / corpus))
    with ThreadPoolExecutor(24) as pool:
        answers = list(pool.map(lambda row: resolve(row[1]), rows))
    answered = sum(1 for a in answers if a)
    if answered < 0.9 * len(rows):
        sys.exit(f'{corpus}: only {answered} of {len(rows)} names answered; nothing written')
    lines = []
    for (category, host), ips in zip(rows, answers):
        # Iran's resolvers answer some names with the national network's 10.x, and blocked ones with 10.10.34.x.
        for ip in sorted({ip for ip in ips if ipaddress.ip_address(ip).is_global}, key=socket.inet_aton):
            lines.append(f'{ip} {category} {host}\n')
    head = (f'# tools/shikoo-iran-first.py, {datetime.date.today()}: tools/{corpus} ({len(rows)} names, {answered} '
            f'answered) {how}.\n# One line per address of each name, in the corpus order.\n')
    path = ROOT / out
    path.parent.mkdir(exist_ok=True)
    path.write_text(head + ''.join(lines), encoding='utf-8', newline='\n')
    print(f'{out}: {len(lines)} lines from {answered}/{len(rows)} names')


write('shikoo-iran-sites.txt', 'core/shikoo_iran_first.txt',
      lambda host: sorted({ip for s in IRAN_RESOLVERS for ip in udp_a(s, host)}),
      f'resolved from Iran with no proxy by {" and ".join(IRAN_RESOLVERS)}')
write('shikoo-foreign-sites.txt', 'core/testdata/shikoo_foreign_sites.txt', doh_a,
      'resolved by 1.1.1.1 over DoH from outside Iran')
