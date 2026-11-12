#!/usr/bin/env nu

def main [program: string --mpi: string = ""] {
  let image = if $mpi == "" { $program } else { $"($program)_($mpi)" }
  cd ($env.HOME | path join Code_Program $program)

  let log_dir = ($env.HOME | path join ".cache" "apptainer-build")
  mkdir $log_dir
  let log_file = ($log_dir | path join $"(date now | format date '%Y%m%d-%H%M%S-%f')_($image).log")

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
    ^tar -czf $"($program).tar.gz" $"./($source)/" o+e>| tee { save --raw --append $log_file }
  }

  let pending = $"($image).building-(random uuid).sif"
  ^apptainer build --fakeroot $pending $"($image).def" o+e>| tee { save --raw --append $log_file }
  ^apptainer inspect $pending
  mv -f $pending $image o+e>| tee { save --raw --append $log_file }
}
