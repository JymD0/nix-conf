# Stalwart mail MCP server package (read mail, save drafts, never sends).
# Imported by claude.nix. Call with `import ./stalwart-mail.nix { inherit pkgs; }`.
{ pkgs }:

pkgs.python3.pkgs.buildPythonApplication {
  pname = "stalwart-mail";
  version = "0.1.0";
  src = ../scripts/stalwart-mail;
  format = "pyproject";

  nativeBuildInputs = [ pkgs.python3.pkgs.setuptools ];

  propagatedBuildInputs = with pkgs.python3.pkgs; [ mcp ];

  # unit tests run against a fake imap, no network
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python -m unittest discover -s tests -t .
    runHook postCheck
  '';
}
