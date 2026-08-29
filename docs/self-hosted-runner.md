# Xiaote Mac GitHub Actions runner

The repository workflows require a self-hosted Apple Silicon Mac carrying the
custom `xiaote-mac` label. Jobs remain queued unless that runner is online.

## One-time setup

1. In GitHub, open **Settings → Actions → Runners → New self-hosted runner**.
2. Select **macOS** and **ARM64**, then run GitHub's displayed download and
   configuration commands on the Mac.
3. When prompted for additional labels, enter `xiaote-mac`.
4. Install the runner as a background service using the `svc.sh` command shown
   by GitHub.
5. Select Xcode and complete its one-time setup:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```

The workflow downloads its pinned XcodeGen version and configures Go itself.
The runner account must be able to use Xcode's iOS Simulator and write to its
own DerivedData directory. Keep repository secrets out of the runner folder.
For security, workflows reject pull requests originating from forks; untrusted
code must never execute on the self-hosted Mac.

## Verification

Open **Settings → Actions → Runners** and confirm the runner is **Idle** and
shows all four labels: `self-hosted`, `macOS`, `ARM64`, and `xiaote-mac`.
Then manually start the **Build and verify on Xiaote Mac** workflow.
