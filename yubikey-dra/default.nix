{pkgs}: pkgs.buildGoModule {
  name = "yubikey-dra";
  src = ./.;
  buildInputs = with pkgs; [
    pcsclite systemdLibs
  ];
  nativeBuildInputs = with pkgs; [
    pkg-config
  ];
  vendorHash = "sha256-eHOaIEHxS0xuFSS8VSmagiuhWEyWAE+EjSNHLCUBu2g=";
}
