{
  description = "NeoCode — native macOS SwiftUI client for OpenCode (nix packaging)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }: let
    system = "aarch64-darwin";
    pkgs = nixpkgs.legacyPackages.${system};
    version = "0.8.1-202607081239-babc663";
  in {
    packages.${system}.default = pkgs.stdenvNoCC.mkDerivation {
      pname = "neocode";
      inherit version;

      src = pkgs.fetchurl {
        url = "https://github.com/bonds/NeoCode/releases/download/v${version}/NeoCode.dmg";
        hash = "sha256-knk1RmndhI5wvOE0f0DYtnHtJh1dKa2pJgMLt9l8hn8=";
      };

      sourceRoot = ".";

      nativeBuildInputs = [pkgs._7zz];

      installPhase = ''
        mkdir -p $out/Applications $out/bin
        cp -r NeoCode.app $out/Applications/

        /usr/bin/plutil -remove SUFeedURL $out/Applications/NeoCode.app/Contents/Info.plist 2>/dev/null || true
        /usr/bin/plutil -remove SUEnableAutomaticUpdates $out/Applications/NeoCode.app/Contents/Info.plist 2>/dev/null || true

        # Inject fork version via sed (avoids nix string escape issues):
        MARKETING=$(printf '%s\n' "$version" | cut -d- -f1)
        BUILD_IDENTIFIER=$(printf '%s\n' "$version" | cut -d- -f2-)
        /usr/bin/plutil -replace CFBundleShortVersionString -string "$MARKETING" $out/Applications/NeoCode.app/Contents/Info.plist
        /usr/bin/plutil -replace CFBundleVersion -string "$BUILD_IDENTIFIER" $out/Applications/NeoCode.app/Contents/Info.plist

        find $out/Applications/NeoCode.app -name '*.HFS+' -delete 2>/dev/null || true
        find $out/Applications/NeoCode.app -name '*:com.apple.*' -delete 2>/dev/null || true
        find $out/Applications/NeoCode.app -name '.DS_Store' -delete 2>/dev/null || true

        find $out/Applications/NeoCode.app -name '_CodeSignature' -type d -exec rm -rf {} + 2>/dev/null || true
        /usr/bin/codesign --force --deep --sign - $out/Applications/NeoCode.app

        ln -s $out/Applications/NeoCode.app/Contents/MacOS/NeoCode $out/bin/neocode
      '';

      dontFixup = true;

      meta = {
        description = "Native macOS SwiftUI client for OpenCode (Sparkle auto-updater disabled)";
        homepage = "https://github.com/watzon/NeoCode";
        license = pkgs.lib.licenses.mit;
        platforms = ["aarch64-darwin"];
        mainProgram = "neocode";
      };
    };
  };
}
