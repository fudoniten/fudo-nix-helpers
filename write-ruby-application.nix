{ name, text, pkgs, runtimeInputs ? [ ], checkPhase ? null, ... }:

with pkgs.lib;
let
  rubyExec = let ruby-name = "${name}-ruby";
  in pkgs.writeTextFile {
    name = ruby-name;
    meta.mainProgram = ruby-name;
    executable = true;
    destination = "/bin/${ruby-name}";
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
  };
in pkgs.writeShellScriptBin name (optionalString (runtimeInputs != [ ]) ''
  export PATH="${makeBinPath runtimeInputs}:$PATH"
'' + ''
  ${rubyExec}
'')
