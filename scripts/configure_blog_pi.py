"""Reuse a Pi-local OpenAI key for BikeNavi without transferring it to the Mac."""
import argparse
import json
import shlex
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', required=True, help='Absolute Pi-local .env path containing OPENAI_API_KEY')
parser.add_argument('--model', required=True, help='Responses API model with web search and Structured Outputs')
args = parser.parse_args()

remote = r'''
from pathlib import Path
import json, os, sys
settings=json.loads(sys.argv[1])
root=Path('/srv/bikenavi')
if not (root/'.bikenavi-owned').is_file(): raise SystemExit('BikeNavi-Zielverzeichnis nicht gekennzeichnet.')
source=Path(settings['source'])
if not source.is_absolute(): raise SystemExit('Absolute Quelldatei erforderlich.')
def values(text):
    result={}
    for line in text.splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key,value=line.split('=',1)
            result[key.strip()]=value.strip().strip('"').strip("'")
    return result
key=values(source.read_text()).get('OPENAI_API_KEY','')
if not key or '\n' in key: raise SystemExit('Kein gültiger OpenAI-Schlüssel in der Quelle.')
model=settings['model']
if not model or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._' for c in model): raise SystemExit('Ungültiger Modellname.')
changes={'BLOG_OPENAI_API_KEY':key,'BLOG_OPENAI_MODEL':model,'BLOG_WEB_SEARCH':'true'}
file=root/'.env'
lines=[line for line in file.read_text().splitlines() if line.split('=',1)[0].strip() not in changes]
text='\n'.join(lines+[name+'='+value for name,value in changes.items()])+'\n'
temporary=root/'.env.blog-tmp'
fd=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
with os.fdopen(fd,'w') as handle: handle.write(text)
os.replace(temporary,file)
file.chmod(0o600)
print('BikeNavi-KI auf dem Pi konfiguriert. Modell: '+model+'. Schlüssel bleibt auf dem Pi.')
'''
command = 'python3 -c ' + shlex.quote(remote) + ' ' + shlex.quote(json.dumps(vars(args)))
subprocess.run(['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', 'pi5', command], check=True)
