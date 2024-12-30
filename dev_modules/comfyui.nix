{ config, lib, pkgs, ... }:

with lib;
{
  options.modules.comfyui = {
    enable = mkEnableOption "ComfyUI setup";
  };

  config = mkIf config.modules.comfyui.enable {
    # Install required packages
    home.packages = with pkgs; [
      python312
      python312Packages.pip
      python312Packages.envs
      git
      gcc
      gcc-unwrapped
      glibc
      stdenv.cc.cc.lib
      pkg-config
    ];

    # Enable nix-direnv
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # Create Dev directory and set up ComfyUI
    home.activation = {
      createComfyUI = lib.hm.dag.entryAfter ["writeBoundary"] ''
        # Create Dev directory if it doesn't exist
        $DRY_RUN_CMD mkdir -p $VERBOSE_ARG $HOME/Dev

        # Clone ComfyUI if it doesn't exist
        if [ ! -d "$HOME/Dev/ComfyUI" ]; then
          ${pkgs.git}/bin/git clone https://github.com/comfyanonymous/ComfyUI.git $HOME/Dev/ComfyUI
          
          # Create development files
          cat > "$HOME/Dev/ComfyUI/flake.nix" << 'EOF'
{
  description = "ComfyUI development environment";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.''${system};
    in {
      devShells.''${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          python312
          python312Packages.pip
          python312Packages.virtualenv
          gcc
          gcc-unwrapped
          pkg-config
          stdenv.cc.cc.lib
        ];

        shellHook = '''
          echo "Loading ComfyUI environment..."

          # Create and activate virtual environment if it doesn't exist
          if [ ! -d ".venv" ]; then
            echo "Creating virtual environment..."
            python -m venv .venv
            source .venv/bin/activate
            pip install --upgrade pip
            
            # Ensure the virtual environment can find system libraries
            LIBSTDCXX=$(find ${pkgs.stdenv.cc.cc.lib}/lib -name "libstdc++.so.*" | head -n 1)
            if [ -n "$LIBSTDCXX" ]; then
              mkdir -p .venv/lib
              ln -sf $LIBSTDCXX .venv/lib/
            fi
            
            pip install -r requirements.txt
          else
            source .venv/bin/activate
          fi

          # Set up environment variables
          CWD=$(pwd)
          export PYTHONPATH="$CWD"
          export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH"

          # NVIDIA-specific environment setup
          if [ -d "/run/opengl-driver" ]; then
            export LD_LIBRARY_PATH="/run/opengl-driver/lib:$LD_LIBRARY_PATH"
          fi
          
          # Add Vulkan paths if available
          if [ -d "/run/opengl-driver/share/vulkan" ]; then
            export VK_LAYER_PATH="/run/opengl-driver/share/vulkan/explicit_layer.d"
          fi

          # Check for NVIDIA GPU
          if command -v nvidia-smi &> /dev/null; then
            echo "NVIDIA GPU detected"
            nvidia-smi --query-gpu=name --format=csv,noheader
          else
            echo "Warning: No NVIDIA GPU detected"
          fi
          
          echo "Environment ready!"
        ''';
      };
    };
}
EOF

          cat > "$HOME/Dev/ComfyUI/.envrc" << 'EOF'
watch_file flake.nix
watch_file flake.lock
watch_file requirements.txt
use flake
EOF

          # Initialize new git repository
          cd "$HOME/Dev/ComfyUI"
          rm -rf .git
          ${pkgs.git}/bin/git init
          ${pkgs.git}/bin/git add .
          ${pkgs.git}/bin/git config --local user.email "local@dev.env"
          ${pkgs.git}/bin/git config --local user.name "Dev Environment"
          ${pkgs.git}/bin/git commit -m "Initial commit"
          
          # Add remote for updates
          ${pkgs.git}/bin/git remote add origin https://github.com/comfyanonymous/ComfyUI.git
          ${pkgs.git}/bin/git fetch origin
        fi

        # Always ensure direnv is allowed
        if [ -f "$HOME/Dev/ComfyUI/.envrc" ]; then
          ${pkgs.direnv}/bin/direnv allow "$HOME/Dev/ComfyUI"
        fi
      '';
    };
  };
}
