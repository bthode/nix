Update lock file

Run this command from the pwd where the flake.nix file is located.

sudo nix flake update

# Clean up old generations and unused packages

    sudo nix-collect-garbage -d
