cask "signalladder" do
  version "1.0.0"
  sha256 "e6f37b8efaa6789a18765352ba47035920655db5995a8fb08755f9674b73d56c"

  url "https://github.com/JWhite212/SignalLadder/releases/download/v#{version}/SignalLadder-#{version}.dmg"
  name "SignalLadder"
  desc "Sounds or speaks only for the notifications your rules pick out"
  homepage "https://github.com/JWhite212/SignalLadder"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "SignalLadder.app"

  uninstall quit: "com.jamiewhite.signalladder"

  zap trash: [
    "~/Library/Application Support/com.jamiewhite.signalladder",
    "~/Library/Preferences/com.jamiewhite.signalladder.plist",
  ]
end
