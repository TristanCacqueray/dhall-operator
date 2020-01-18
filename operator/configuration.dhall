{- The operator configuration.

Note: run `make config-update` to update files before commiting changes
 -}
let version = "0.0.2"

in  { year = "2020"
    , author = "Red Hat"
    , version = version
    , image = "quay.io/software-factory/dhall-operator:${version}"
    , group = "softwarefactory-project.io"
    , crd =
        { kind = "Dhall"
        , plural = "dhalls"
        , singular = "dhall"
        , role = "dhall"
        }
    }
