#!/usr/bin/env zsh

autoload colors
if [[ "$terminfo[colors]" -gt 8 ]]; then
    colors
fi

# save current working directory
save_cwd=`pwd`

src_base=$(git rev-parse --show-toplevel)

# source (devel) paths
helen_src_base=${src_base}
helen_extra=${helen_src_base}/extra
helen_extra_bin=${helen_extra}/bin
helen_build_prod=${helen_src_base}/_build/prod

# prod install path and filenames
helen_base=/usr/local/helen
helen_base_new=${helen_base}.new
helen_base_old=${helen_base}.old
helen_bin=${helen_base}/bin

# helen prod release tar ball
helen_tarball=${helen_build_prod}/helen.tar.gz
