# Package a Ruby script as a standalone application
#
# This helper creates a Ruby script with proper shebang and runtime environment,
# wrapped in a shell script that sets up PATH and RUBYLIB.
#
# Example usage:
#   writeRubyApplication {
#     name = "my-script";
#     pkgs = pkgs;
#     text = ''
#       puts "Hello, world!"
#     '';
#     runtimeInputs = [ pkgs.curl ];  # Added to PATH
#     libInputs = [ ./lib ];          # Added to RUBYLIB
#   }
#
# Parameters:
#   name: Name of the resulting executable
#   text: Ruby script content (without shebang)
#   pkgs: Nixpkgs package set
#   runtimeInputs: Packages to add to PATH (default: [])
#   ruby: Ruby interpreter to use (default: pkgs.ruby_3_3)
#   libInputs: Paths to add to RUBYLIB (default: [])
#   checkPhase: Custom check phase for validation (default: null)

{ name, text, pkgs, runtimeInputs ? [ ], ruby ? pkgs.ruby_3_3, libInputs ? [ ]
, lib ? pkgs.lib, writeTextFile ? pkgs.writeTextFile
, writeShellScriptBin ? pkgs.writeShellScriptBin, checkPhase ? null }:

with lib;
let
  # The Ruby script itself, with shebang
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
  };

  # Helper to build RUBYLIB path string
  makeLibPath = libPaths: concatStringsSep ":" (map (path: "${path}") libPaths);

# Wrapper script that sets up environment and invokes the Ruby script
in writeShellScriptBin name (
  # Add runtime inputs to PATH if specified
  optionalString (runtimeInputs != [ ]) ''
    export PATH="${makeBinPath runtimeInputs}:$PATH"
  ''
  # Add lib inputs to RUBYLIB if specified
  + (optionalString (libInputs != [ ]) ''
    export RUBYLIB="${makeLibPath libInputs}"
  '')
  # Invoke the Ruby script, passing through all arguments
  + ''
    ${rubyExec}/bin/${ruby-name} "$@"
  ''
)
