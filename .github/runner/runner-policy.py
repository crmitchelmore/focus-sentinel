#!/usr/bin/env python3
"""Refuse untrusted jobs and serialize CI on the shared desktop."""
import fcntl, json, os, pathlib, subprocess, sys, time
ROOT = pathlib.Path('/Users/bravostation/actions-runners/admin')
REPOS = {'crmitchelmore/' + name for name in ('focus-sentinel', 'pasta', 'justspeaktoit', 'tally', 'family-watch-activity-tracker', 'todo', 'quality-software')}
ACTORS = {'crmitchelmore', 'bravostation'}

def trusted(env, event):
    repo = env.get('GITHUB_REPOSITORY', '')
    if repo not in REPOS or event.get('repository', {}).get('full_name') != repo:
        return False
    if env.get('GITHUB_ACTOR') not in ACTORS or env.get('GITHUB_TRIGGERING_ACTOR', env.get('GITHUB_ACTOR')) not in ACTORS:
        return False
    kind = env.get('GITHUB_EVENT_NAME')
    if kind == 'workflow_dispatch':
        return True
    if kind == 'pull_request':
        # Explicit owner-approved Alpha rollout revisions; never authorise forks
        # or later, unreviewed revisions merely because the PR number matches.
        pr = event.get('pull_request', {})
        try:
            approved = json.loads((ROOT / 'approved-pull-requests.json').read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            approved = {}
        expected = approved.get(repo, {}).get(str(event.get('number')), '')
        if expected and pr.get('head', {}).get('repo', {}).get('full_name') == repo and pr.get('head', {}).get('sha') == expected:
            return True
    if repo not in {'crmitchelmore/focus-sentinel', 'crmitchelmore/family-watch-activity-tracker'}:
        return False
    if kind == 'push':
        return True
    if kind == 'pull_request':
        return event.get('pull_request', {}).get('head', {}).get('repo', {}).get('full_name') == repo
    return False

def process(pid):
    r = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'ppid=,lstart=,comm='], capture_output=True, text=True)
    if r.returncode or not r.stdout.strip():
        return None
    parts = r.stdout.strip().split(None, 6)
    return (int(parts[0]), ' '.join(parts[1:6]), parts[6]) if len(parts) == 7 else None

def worker():
    pid = os.getppid()
    for _ in range(16):
        p = process(pid)
        if not p:
            break
        if p[2].endswith('/Runner.Worker'):
            return {'pid': pid, 'started': p[1], 'repo': os.environ.get('GITHUB_REPOSITORY', '')}
        pid = p[0]
    raise RuntimeError('Cannot identify this job worker; refusing an uncoordinated job')

def alive(owner):
    p = process(owner.get('pid', 0))
    return bool(p and p[1] == owner.get('started') and p[2].endswith('/Runner.Worker'))

def lease():
    owner = worker()
    state = ROOT / 'active-job.json'
    deadline = time.monotonic() + 3600
    printed = False
    while time.monotonic() < deadline:
        with (ROOT / 'job-lock').open('a+') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                previous = json.loads(state.read_text())
            except (FileNotFoundError, json.JSONDecodeError):
                previous = {}
            if not previous or not alive(previous) or previous == owner:
                state.write_text(json.dumps(owner))
                print('Local CI slot acquired for', owner['repo'], flush=True)
                return
        if not printed:
            print('Waiting for the other local CI job to finish; no workspace steps have started.', flush=True)
            printed = True
        time.sleep(5)
    raise RuntimeError('Local CI slot remained busy for one hour; retry when the machine is free')

def main():
    if '--lease-only' not in sys.argv:
        with open(os.environ.get('GITHUB_EVENT_PATH', '')) as f:
            event = json.load(f)
        if not trusted(os.environ, event):
            raise RuntimeError('This personal Mac accepts owner-triggered local workflows and trusted private-repository CI only; fork jobs are refused')
        print('Trusted local runner event accepted.', flush=True)
    lease()

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('::error::' + str(error), file=sys.stderr)
        sys.exit(1)
