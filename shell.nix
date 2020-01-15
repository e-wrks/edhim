# this defines the Nix env to run this Haskell project
with (import ./. { });
haskellPackages.shellFor {
  packages = p: with p; [ edh edhim ];
  nativeBuildInputs = [ pkgs.cabal-install ];
  withHoogle = true;
}
