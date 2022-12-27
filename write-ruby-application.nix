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
  checkPhase = if checkPhase == null then ''
    runHook preCheck
    HOME=$(mktemp -d rubocop-XXXXXXXX)
    ${pkgs.rubocop}/bin/rubocop \
      --except Style/ColonMethodCall,Style/BlockDelimiters,Style/StringLiterals \
      --cache false
      "$target"
    runHook postCheck
  '' else
    checkPhase;
}
