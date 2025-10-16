function convert_to_gif() {
  local input="${1:?path of video to convert to gif}"
  if ! [ -f "${input}" ]; then
    log::err "Unable to find input file | input='${input}'"
    return 1
  fi

  # Get absolute paths and filenames
  local input_abs="$(realpath "${input}")"
  local input_dir="$(dirname "${input_abs}")"
  local input_basename="$(basename "${input_abs}")"
  local output_basename="${input_basename%.*}.gif"

  # Form and run the ffmpeg command with a docker container
  local container_volume="/data"
  local docker_args=(
    run
    --rm
    --volume "${input_dir}:${container_volume}"
    jrottenberg/ffmpeg
  )
  local ffmpeg_args=(
      -i "${container_volume}/${input_basename}"
      -vf "fps=15"
      -gifflags +transdiff
      -y
      "${container_volume}/${output_basename}"
  )
  if ! run_scroll docker "${docker_args[@]}" "${ffmpeg_args[@]}"; then
    log::err "Failed to convert input into gif"
    return 1
  fi
  local output="${input_dir}/${output_basename}"

  # log success and open the gif
  local gif_viewer="/Applications/Google Chrome.app"
  run_cmd open -a "${gif_viewer}" "${output}"
  log::info "Created gif at {output} | output='${output}'"
}
