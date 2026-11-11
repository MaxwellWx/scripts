#!/usr/bin/env nu

def main [program: string --mpi: string = ""] {
  let image = if $mpi == "" { $program } else { $"($program)_($mpi)" }
  cd ($env.HOME | path join Code_Program $program)

  if $mpi == "" {
    let source = match $program {
      smilei => "Smilei"
      smilei_fatido => "Smilei_FaTiDo"
      smilei_fatido_no_rad_push => "Smilei_FaTiDo_no_rad_push"
      smilei_spin => "Smilei_Spin"
      fatido => "FaTiDo"
      warpx => "WarpX"
      _ => { error make {msg: $"Unknown program: ($program)"} }
    }
    ^tar -czf $"($program).tar.gz" $"./($source)/"
  }

  let pending = $"($image).building-(random uuid).sif"
  ^apptainer build --fakeroot $pending $"($image).def"
  ^apptainer inspect $pending
  mv -f $pending $image
}
