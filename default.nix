{ overlays ? [ ], ... }@args:
import (
# to use a version of Edh from github
  builtins.fetchTarball {
    url = "https://github.com/e-wrks/edh/archive/0.2.0.0.tar.gz";
    sha256 = "0fsckwasy2gf67rz72acq0af3m31mx2ljj2xdz1dvrlwpryb6q85";
  }

  # to use the version of Edh checked out locally
  # ../edh
) (args // {
  overlays = [
    (self: super:
      let
        myHaskellPackageSet = super.haskellPackages.override {
          overrides = hself: hsuper: {
            edhim = hself.callCabal2nix "edhim" ./edhim { };
          };
        };
      in {
        # expose as a top-level Nix package too
        edhim = myHaskellPackageSet.edhim;

        # override the Haskell package set at standard locations
        haskellPackages = myHaskellPackageSet;
        haskell = super.haskell // {
          packages = super.haskell.packages // {
            ghcWithMyPkgs = myHaskellPackageSet;
          };
        };
      })
  ] ++ overlays;
})
