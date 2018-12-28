{ nixpkgs ? import <nixpkgs> {}, compiler ? "default", doBenchmark ? false }:

let

  inherit (nixpkgs) pkgs;

  f = { mkDerivation, aeson, array, attoparsec, base
      , base64-bytestring, blaze-builder, bytestring, directory, entropy
      , http-client, lucid, monad-logger, network, pwstore-fast, scotty
      , sqlite-simple, stache, stdenv, text, unix, unordered-containers
      , vector, wai, wai-extra, wai-middleware-static
      }:
      mkDerivation {
        pname = "satsbacker";
        version = "0.1.0.0";
        src = ./.;
        isLibrary = false;
        isExecutable = true;
        executableHaskellDepends = [
          aeson array attoparsec base base64-bytestring blaze-builder
          bytestring directory entropy http-client lucid monad-logger network
          pwstore-fast scotty sqlite-simple stache text unix
          unordered-containers vector wai wai-extra wai-middleware-static
        ];
        homepage = "https://satsbacker.com";
        description = "An uncensorable membership platform for creators and backers";
        license = stdenv.lib.licenses.mit;
      };

  haskellPackages = if compiler == "default"
                       then pkgs.haskellPackages
                       else pkgs.haskell.packages.${compiler};

  variant = if doBenchmark then pkgs.haskell.lib.doBenchmark else pkgs.lib.id;

  drv = variant (haskellPackages.callPackage f {});

in

  if pkgs.lib.inNixShell then drv.env else drv
