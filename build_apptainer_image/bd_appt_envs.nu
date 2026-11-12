#!/usr/bin/env nu

def main [program: string --mpi: string = ""] {
  let base = if $mpi == "" { $program } else { $"($program)_($mpi)" }
  let image = $"($base)_env"
  cd ($env.HOME | path join Code_Program $program)

  let log_dir = ($env.HOME | path join ".cache" "apptainer-build")
  mkdir $log_dir
  let log_file = ($log_dir | path join $"(date now | format date '%Y%m%d-%H%M%S-%f')_($image).log")

  let pending = $"($image).building-(random uuid).sif"
  ^apptainer build --fakeroot $pending $"($image).def" o+e>| tee { save --raw --append $log_file }
  ^apptainer inspect $pending
  mv -f $pending $image o+e>| tee { save --raw --append $log_file }
}
