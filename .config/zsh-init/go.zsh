## Define a GOPATH. This is the folder `go` will use to store artifacts
## (compiled or downloaded). It's also where we can place our 'src' folder.
##
## See 'https://go.dev/doc/gopath_code' for more information
#export GOPATH="/usr/local/go"
#
## Make sure that we can execute stuff we've downloaded/created via Go
prepend_to_path "$(go env GOPATH)/bin"
