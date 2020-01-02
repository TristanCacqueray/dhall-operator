{ type = (../types/ServiceType.dhall).Other
, privileged = False
, ports = None (List ../types/Port.dhall)
, init-containers = None (List ../types/Container.dhall)
, volume-size = None Natural
}
