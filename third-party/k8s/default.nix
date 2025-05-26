{ lab, pkgs, lib, lock, ... }: {
  kubeVersion = lock.k8s.version;
  cuePkg =  pkgs.buildGoModule {    
    version = lock.k8s.version;
    pname = "vendor-k8s";    
    src = builtins.path {
      filter = path: type: !(lib.strings.hasSuffix ".nix" path);
      path = ./.;
    };
    nativeBuildInputs = [ lab.third-party.cue ];    
    vendorHash = lock.k8s.vendorHash;
    buildPhase = ''    
      cue get go k8s.io/api/...    
      cue get go k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1    
      go build extra.go
      cat <<EOF > cue.mod/module.cue
        module: "k8s.io"
        language: version: "v0.13.0"
        source: kind: "self"
      EOF
      (cd cue.mod/gen; find k8s.io -regex 'k8s.io\/.*\/types_go_gen\.cue') | grep -v 'k8s.io/apimachinery' | xargs dirname | uniq | grep --invert-match 'k8s.io/apimachinery/pkg/runtime' | xargs ./extra ./cue.mod/gen
    '';    
    installPhase = ''    
      mv cue.mod/gen/k8s.io "$out"    
      rm -rf cue.mod/gen
      mv cue.mod/ "$out/"
    '';    
    passthru = {
      module-name = "k8s.io";
    };
  }; 
}
