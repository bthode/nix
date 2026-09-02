# Colima container runtime, work host only.
#
# Two responsibilities:
#   1. The VM template Colima stamps new instances from. A read-only store
#      symlink is safe here because Colima only ever reads the template.
#   2. Repairing ~/.docker/config.json (added in a later task). That file is
#      merged rather than symlinked, because `docker login` and Colima both
#      need to write it.
#
# The VM is started manually with `colima start`; there is deliberately no
# launchd agent, so the VM's 8 GB is only committed when it is wanted.
{
  pkgs,
  lib,
  isWork,
  ...
}:

lib.mkIf isWork {
  home.file.".colima/_templates/default.yaml".source = ./colima-template.yaml;
}
