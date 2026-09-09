# Persistent local CI on bravo-mini

Seven repository-scoped GitHub Actions runners are installed under `/Users/bravostation/actions-runners`: focus-sentinel, family-watch-activity-tracker, justspeaktoit, pasta, tally, todo and quality-software. Pasta existed before this setup. The six new registrations use runner 2.337.0 for macOS ARM64. Each registration has its own service, credentials and work directory.

The services are macOS LaunchAgents. They restart automatically in the bravostation login session. The Mac must be awake and that user logged in; this is not a server that works while the machine is off or before login.

## Run a job

Open Actions > Local CI > Run workflow. Choose `verify` to check the runner and Xcode without checking out project code. Choose `build` to build and perform the repository's non-UI checks. The default ref is main. These workflows contain no UI tests or hosted-runner fallback and upload no cache or artifact storage.

Focus's separate Build and verify workflow runs its full gate locally only after explicitly selecting the UI-test confirmation input. Obtain Chris's fresh approval before running it. Do not dispatch an older branch's hosted workflow; bring the current workflow configuration into that branch first.

New runners route through `[bravo-mini-local, macOS, ARM64]`. Pasta retains `[pasta-local, macos-arm64]` so its current jobs and registration are undisturbed. Existing free public-repository hosted jobs remain available. Private Family Watch CI now routes its web and watchOS unit-test jobs locally. This setup does not migrate Linux-only, Android or release-specific lanes from public CI.

## Scheduling and trust

The job-started hook lives under `/Users/bravostation/actions-runners/admin/hooks`. It verifies the repository and trigger, then waits for a shared machine lease tied to the live Runner.Worker PID and start time. A stale lease is reclaimed automatically. Each runner has its own workspace. Fork jobs are refused. Public registrations accept trusted manual dispatch; any separately approved PR exceptions must match the precise repository, PR and commit recorded locally. The existing Pasta trust hook remains in front of the shared lease hook.

This queue coordinates GitHub jobs only. It does not coordinate an agent's independent local Xcode process. These are user-level processes, not isolated VMs. Never broaden the trust policy to arbitrary external pull requests on this personal Mac.

## Service administration

In a runner directory, use `./svc.sh status`, `./svc.sh stop` or `./svc.sh start`. Do not stop or reconfigure a busy peer runner. Logs are under `_diag`; workspaces are under `_work`. Registration credentials and tokens must never be committed. The hook source copies alongside this document are recovery references; the active versions are in the admin directory, so compare them before restoring.

Disk space is shared with other agents. Installation briefly exhausted the external volume on 9 September, then succeeded after space became available. Check `df -h` before large builds. Only remove disposable outputs owned by the current task; do not delete peer work or runner data blindly.

## Verified rollout, 9 September 2026

Tool-only jobs passed on Focus (34413143210), Family Watch (34413145715), Todo (34413147770) and Quality Software (34413198688). The Family Watch job log demonstrates waiting for the shared slot before its steps ran. No app UI tests were started by this rollout.

The manual workflow is published on main for those four repositories. Remaining protected-branch changes are Pasta PR 134, JustSpeakToIt PR 1066 and Tally PR 179. Their required checks have not been bypassed. Their Local CI workflows become dispatchable after merge; installation alone is not end-to-end verification of those pending workflows. Track the remaining work in Beads focus-wfe7 and the existing Notion ENG-GITHUB-BUDGET record.
