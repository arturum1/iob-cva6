# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# Nix environment with dependencies for SpinalHDL

{ pkgs ? import <nixpkgs> {}}:
  pkgs.mkShell {
    # nativeBuildInputs is usually what you want -- tools you need to run
    nativeBuildInputs = [ 
        pkgs.haskellPackages.sv2v
    ];
}

