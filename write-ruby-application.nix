{ name, text, pkgs, runtimeInputs ? [ ], checkPhase ? null, ... }:
pkgs.writeTextFile {
  inherit name;
  meta.mainProgram = name;
  executable = true;
  destination = "/bin/${name}";
  text = ''
    #!${pkgs.ruby_3_1}/bin/ruby

    ${text}
  '';
  checkPhase = let
    excludedChecks = [
      "Style/ColonMethodCall"
      "Style/BlockDelimiters"
      "Style/StringLiterals"
      "Naming/FileName"
      "Layout/TrailingEmptyLines"
      "Lint/ScriptPermission"
    ];
  in if checkPhase == null then ''
    runHook preCheck
    HOME=$(mktemp -d rubocop-XXXXXXXX)
    ${pkgs.rubocop}/bin/rubocop --except ${
      pkgs.lib.concatStringsSep "," excludedChecks
    } --cache false "$target"
    runHook postCheck
  '' else
    checkPhase;
}
