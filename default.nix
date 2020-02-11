{ overlays ? [ ], ... }@args:
import (
# to use a version of Edh from github
  builtins.fetchTarball {
    url = "https://github.com/e-wrks/edh/archive/0.1.0.1.tar.gz";
    sha256 = "00bcpx6liszkp7arykxmb971i2a3mpkpsgziig450iz884b9vdcw";
  }

  # to use the version of Edh checked out locally
  # ../edh
) (args // {
  overlays = (args.overlays or [ ]) ++ [
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
  ];
})
