#!/usr/bin/env -S nix develop .#update-script --command python
import tomlkit
import os
import subprocess
import json
from git.repo.base import Repo
import tempfile
import shutil
import inspect

script_dir = os.path.dirname(os.path.realpath(__file__))

with open(os.path.join(script_dir, "../../lock.toml"), "r") as f:
  lock = tomlkit.load(f)

version = lock["k8s"]["version"]
k8s_go_version = '.'.join(['v0'] + version.split('.')[1:])

with open(os.path.join(script_dir, "go.mod"), "w") as mod:
  mod.write(inspect.cleandoc(f"""
    module pythoner6.dev/homelab/third-party/k8s

    go 1.24.2

    require (
    	cuelang.org/go {lock["cue"]["version"]}
    	k8s.io/api {k8s_go_version}
    	k8s.io/apiextensions-apiserver {k8s_go_version}
    	k8s.io/apimachinery {k8s_go_version}
    )
  """))

subprocess.run(["go", "mod", "download", f"k8s.io/api@{k8s_go_version}"], check=True, cwd=script_dir)
apis = subprocess.run(["go", "list", "k8s.io/api/..."], cwd=script_dir, check=True, encoding='utf-8', stdout=subprocess.PIPE).stdout
apis = "\n".join([f"  _ \"{line}\"" for line in apis.splitlines()])

with open(os.path.join(script_dir, "main.go"), "w") as main:
  main.write(inspect.cleandoc(f"""
    package main

    import (
    {apis}
      _ "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
      _ "k8s.io/apimachinery/pkg/types"
    )
  """))

subprocess.run(["go", "mod", "tidy"], check=True, cwd=script_dir)

with tempfile.TemporaryDirectory() as tmp:
  subprocess.run([
    "go", "mod", "vendor", "-o", tmp
  ], cwd=script_dir, check=True)
  hash = subprocess.run([
    "nix-hash", "--sri", "--type", "sha256", os.path.join(tmp)
  ], check=True, encoding='utf-8', stdout=subprocess.PIPE)

  lock["k8s"]["vendorHash"] = hash.stdout.strip()
  #hash = subprocess.run([
  #  "nix-hash", "--sri", "--type", "sha256", repo_dir
  #], check=True, encoding='utf-8', stdout=subprocess.PIPE)
  #lock["talos"]["talosctl"]["srcHash"] = hash.stdout.strip()
  #lock["talos"]["imager"]["srcHash"] = hash.stdout.strip()

  # TODO: because this can depend on the environment, this is
  #       not as reproducible as I'd like...
  #vendor_env = os.environ.copy()
  #vendor_env['GOWORK'] = 'off'
  #vendor = subprocess.run([
  #  "go", "mod", "vendor"
  #], env=vendor_env, cwd=repo_dir, check=True)
  #hash = subprocess.run([
  #  "nix-hash", "--sri", "--type", "sha256", os.path.join(repo_dir, "vendor")
  #], check=True, encoding='utf-8', stdout=subprocess.PIPE)

  #lock["talos"]["talosctl"]["vendorHash"] = hash.stdout.strip()
  #lock["talos"]["imager"]["vendorHash"] = hash.stdout.strip()

with open(os.path.join(script_dir, "../../lock.toml"), "w") as f:
    tomlkit.dump(lock, f)
