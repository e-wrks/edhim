# this defines the Nix env to run this Haskell project
with (import ./. { });
haskellPackages.edhim.envFunc { withHoogle = true; }
