# Homebrew cask for the locally built IQUNIX-DRIVE app.
#
# The ZIP is produced by `./scripts/make-app.sh` inside this repository, so the
# URL is a local file:// path (no network download, nothing to notarize).
# `scripts/make-app.sh` rewrites the sha256 line below after every package run.
cask "iqunix-drive" do
  version "0.2.0"
  sha256 :no_check

  url "file:///Volumes/MyFiles/Projects/IQUNIX-DRIVE/dist/IQUNIX-DRIVE-0.2.0.zip"

  name "IQUNIX-DRIVE"
  desc "Native macOS configurator for VIA-compatible keyboards (IQUNIX MQ80 included)"
  homepage "https://github.com/iqunix/iqunix-drive"

  depends_on macos: :ventura

  app "IQUNIX-DRIVE.app"

  uninstall quit: "com.iqunix.drive"
end
