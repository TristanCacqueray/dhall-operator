{ Type = ../types/Service.dhall
, default =
    { type = (../types/ServiceType.dhall).Other
    , count = 1
    , privileged = False
    , ports = None (List ../types/Port.dhall)
    , init-containers = None (List ../types/Container.dhall)
    , volume-size = None Natural
    , data-dir = [] : List ../types/Volume.dhall
    }
}
