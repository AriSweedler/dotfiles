function example::jq::drill() {
  local json='
{
  "a": 1,
  "b": 2,
  "c": { "d": 3, "e": 4 },
  "f": [
    { "x0": 0, "x1": 1 },
    { "y0": 0, "y1": 1 },
    { "z0": 0, "z1": 1 }
  ]
}
'
  log::dev "Showing off the capability of 'jq::drill' | json='${json}'"
  jq::drill <<< "${json}"
}
