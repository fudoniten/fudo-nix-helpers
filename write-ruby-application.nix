{ name, text, pkgs, runtimeInputs ? [ ], checkPhase ? null, ... }:
pkgs.writeTextFile {
  inherit name;
  meta.mainProgram = name;
  executable = true;
  destination = "/bin/${name}";
  text = ''
    #!${pkgs.ruby}/bin/ruby

    ${text}
  '';
  checkPhase = let
    excludedChecks = [
      "Style/ColonMethodCall"
      "Style/BlockDelimiters"
      "Style/StringLiterals"
      "Naming/FileName"
    ];
  in if checkPhase == null then ''
    runHook preCheck
    HOME=$(mktemp -d rubocop-XXXXXXXX)
    ${pkgs.rubocop}/bin/rubocop --except ${
      pkgs.lib.concatStringsSep "," excludedChecks
    } --cache false "$target/${name}"
    runHook postCheck
  '' else
    checkPhase;
}
