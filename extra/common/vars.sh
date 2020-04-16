#!/usr/bin/env zsh

autoload colors
if [[ "$terminfo[colors]" -gt 8 ]]; then
    colors
fi

# save current working directory
save_cwd=`pwd`

# source (devel) paths
helen_base=${HOME}/devel/helen
helen_extra=${helen_base}/extra
helen_base=${helen_base}/mcp
helen_build_prod=${helen_base}/_build/prod
mcr_esp_base=${helen_base}/mcr_esp

# mcr build location and prefix
mcr_esp_bin_src=${mcr_esp_base}/build/mcr_esp.bin
mcr_esp_elf_src=${mcr_esp_base}/build/mcr_esp.elf
mcr_esp_prefix=$(git describe)

# prod install path and filenames
helen_base=/usr/local/helen
helen_base_new=${helen_base}.new
helen_base_old=${helen_base}.old
helen_bin=$helen_base/bin

# mcr firmware install path and filenames
www_root=/dar/www/wisslanding/htdocs
mcr_esp_fw_loc=${www_root}/helen/mcr_esp/firmware
mcr_esp_bin=${mcr_esp_prefix}-mcr_esp.bin
mcr_esp_bin_deploy=${mcr_esp_fw_loc}/${mcr_esp_bin}
mcr_esp_elf=${mcr_esp_prefix}-mcr_esp.elf
mcr_esp_elf_deploy=${mcr_esp_fw_loc}/${mcr_esp_elf}

# mcp prod release tar ball
helen_tarball=${helen_build_prod}/helen.tar.gz
