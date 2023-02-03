{ name, text, pkgs, runtimeInputs ? [ ], ruby ? pkgs.ruby_3_1, libInputs ? [ ]
, rubocop ? pkgs.rubocop, checkPhase ? null }:

with pkgs.lib;
let
  ruby-name = "${name}-ruby";
  rubyExec = pkgs.writeTextFile {
    name = ruby-name;
    meta.mainProgram = ruby-name;
    executable = true;
    destination = "/bin/${ruby-name}";
    text = ''
      #!${ruby}/bin/ruby

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
      ${rubocop}/bin/rubocop --except ${
        concatStringsSep "," excludedChecks
      } --cache false "$target"
      runHook postCheck
    '' else
      checkPhase;
  };
  makeLibPath = libPaths: concatStringsSep ":" (map (path: "${path}") libPaths);
in pkgs.writeShellScriptBin name (optionalString (runtimeInputs != [ ]) ''
  export PATH="${makeBinPath runtimeInputs}:$PATH"
'' + (optionalString (libInputs != [ ]) ''
  export RUBYLIB="${makeLibPath libInputs}"
'') + ''
  ${rubyExec}/bin/${ruby-name} $@
'')
