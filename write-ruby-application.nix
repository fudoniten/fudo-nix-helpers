{ name, text, pkgs, runtimeInputs ? [ ], ruby ? pkgs.ruby_3_3, libInputs ? [ ]
, rubocop ? pkgs.rubyPackages_3_3.rubocop, lib ? pkgs.lib
, writeTextFile ? pkgs.writeTextFile
, writeShellScriptBin ? pkgs.writeShellScriptBin, checkPhase ? null }:

with lib;
let
  ruby-name = "${name}-ruby";
  rubyExec = writeTextFile {
    name = ruby-name;
    meta.mainProgram = ruby-name;
    executable = true;
    destination = "/bin/${ruby-name}";
    text = ''
      #!${ruby}/bin/ruby

      ${text}
    '';
    checkPhase = checkPhase;
    ## Damn: uses obsolete packages
    # checkPhase = let
    #   excludedChecks = [
    #     "Style/ColonMethodCall"
    #     "Style/BlockDelimiters"
    #     "Style/StringLiterals"
    #     "Naming/FileName"
    #     "Layout/TrailingEmptyLines"
    #     "Lint/ScriptPermission"
    #   ];
    # in if checkPhase == null then ''
    #   runHook preCheck
    #   HOME=$(mktemp -d rubocop-XXXXXXXX)
    #   ${rubocop}/bin/rubocop --except ${
    #     concatStringsSep "," excludedChecks
    #   } --cache false "$target"
    #   runHook postCheck
    # '' else
    #   checkPhase;
  };
  makeLibPath = libPaths: concatStringsSep ":" (map (path: "${path}") libPaths);
in writeShellScriptBin name (optionalString (runtimeInputs != [ ]) ''
  export PATH="${makeBinPath runtimeInputs}:$PATH"
'' + (optionalString (libInputs != [ ]) ''
  export RUBYLIB="${makeLibPath libInputs}"
'') + ''
  ${rubyExec}/bin/${ruby-name} $@
'')
