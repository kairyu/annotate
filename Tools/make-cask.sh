#!/bin/sh
#
# Render the Homebrew cask for a released version.
#
#   sh Tools/make-cask.sh <version> <sha256> [url]
#
# Prints the cask to stdout. The release workflow uses it to attach a cask to the
# release and to update the tap; run it by hand to inspect what either will produce.
#
# A cask rather than a formula: formulae build command-line software from source,
# casks install prebuilt macOS applications. This ships an .app — with the MCP
# server sealed inside it, so there is nothing else to install.
#
# Three things about this cask are not boilerplate.
#
# livecheck uses the repository's TAGS, not :github_latest. Every 0.x release is
# published as a GitHub pre-release (see release.yml), and both GitHub's "latest
# release" and Homebrew's release strategies skip pre-releases — so either of
# those would report no version at all until 1.0.
#
# The uninstall `quit` stops the running app before its bundle is replaced, so an
# upgrade never leaves a stale process holding the control socket.
#
# zap removes Application Support/Annotate, which holds the control socket and
# the approved-hosts list. A plain uninstall keeps it on purpose: losing the host
# approvals on every upgrade would make each agent ask again.
set -eu

VERSION="${1:?usage: make-cask.sh <version> <sha256> [url]}"
SHA="${2:?usage: make-cask.sh <version> <sha256> [url]}"
# The URL keeps Homebrew's #{version} interpolation so a version bump only ever
# touches the version and sha256 lines. Built with a plain if rather than
# "${3:-...}", because that form ends at the first unescaped } — which is inside
# #{version}, and would silently produce a mangled URL.
if [ "$#" -ge 3 ]; then
    URL="$3"
else
    URL='https://github.com/kairyu/annotate/releases/download/v#{version}/Annotate-v#{version}.zip'
fi

# Unquoted heredoc so VERSION/SHA/URL expand. Nothing below may contain a
# backtick or a bare dollar sign, since the shell would act on either.
cat <<CASK
cask "annotate" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "${URL}",
      verified: "github.com/kairyu/annotate/"
  name "Annotate"
  desc "Lets an AI agent draw hand-drawn annotations on your screen"
  homepage "https://github.com/kairyu/annotate"

  livecheck do
    url "https://github.com/kairyu/annotate.git"
    regex(/^v?(\\d+(?:\\.\\d+)+)\$/i)
  end

  # The deployment target. A bare symbol means "this or newer" to Homebrew.
  depends_on macos: :sonoma

  app "Annotate.app"

  uninstall quit: "me.kairyu.annotate"

  zap trash: [
    "~/Library/Application Support/Annotate",
    "~/Library/Preferences/me.kairyu.annotate.plist",
  ]

  caveats <<~EOS
    Annotate needs the Accessibility permission to locate controls on screen.
    macOS asks on first launch; it is under System Settings > Privacy & Security.

    The MCP server ships inside the app. Point your agent at:
      #{appdir}/Annotate.app/Contents/MacOS/annotate-mcp
  EOS
end
CASK
