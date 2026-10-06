"""Pi env merge is tested with fake secrets, without SSH or reading real .env."""
import ast
from io import StringIO
from pathlib import Path
import sys


def test_deployment_keeps_pi_local_blog_key(tmp_path, monkeypatch):
    source = Path(__file__).resolve().parents[2] / 'scripts/deploy_pi.py'
    tree = ast.parse(source.read_text())
    code = next(n.value.value for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'merge_environment' for t in n.targets))
    code = code.replace('Path("/srv/bikenavi")', 'Path('+repr(str(tmp_path))+')')
    target = tmp_path / '.env'
    target.write_text('BIKENAVI_TOKEN=old-fake\nBLOG_OPENAI_API_KEY=pi-only-fake\nBLOG_OPENAI_MODEL=test-model\nBLOG_WEB_SEARCH=true\n')
    monkeypatch.setattr(sys, 'stdin', StringIO('BIKENAVI_TOKEN=new-fake\nBLOG_OPENAI_API_KEY=\n'))
    exec(compile(code, '<env-merge>', 'exec'), {})
    assert target.read_text().splitlines() == ['BIKENAVI_TOKEN=new-fake', 'BLOG_OPENAI_API_KEY=pi-only-fake', 'BLOG_OPENAI_MODEL=test-model', 'BLOG_WEB_SEARCH=true']
    assert target.stat().st_mode & 0o777 == 0o600
    monkeypatch.setattr(sys, 'stdin', StringIO('BIKENAVI_TOKEN=new-fake\nBLOG_OPENAI_API_KEY=explicit-fake\nBLOG_OPENAI_MODEL=next-model\nBLOG_WEB_SEARCH=false\n'))
    exec(compile(code, '<env-merge>', 'exec'), {})
    assert 'BLOG_OPENAI_API_KEY=explicit-fake' in target.read_text()
    assert 'pi-only-fake' not in target.read_text()
