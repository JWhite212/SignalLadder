cask "signalladder" do
  version "1.1.0"
  sha256 "bde992827c985ac507a937edaba0cfc28d3031add5ae3c6ccb6d56214503d120"

  url "https://github.com/JWhite212/SignalLadder/releases/download/v#{version}/SignalLadder-#{version}.dmg"
  name "SignalLadder"
  desc "Sounds or speaks only for the notifications your rules pick out"
  homepage "https://github.com/JWhite212/SignalLadder"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "SignalLadder.app"

  uninstall quit: "com.jamiewhite.signalladder"

  zap trash: [
    "~/Library/Application Support/com.jamiewhite.signalladder",
    "~/Library/Preferences/com.jamiewhite.signalladder.plist",
  ]
end
