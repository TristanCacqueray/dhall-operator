{ name : Text
, count : Natural
, type : ./ServiceType.dhall
, privileged : Bool
, ports : Optional (List ./Port.dhall)
, container : ./Container.dhall
, init-containers : Optional (List ./Container.dhall)
, volume-size : Optional Natural
, data-dir : List ./Volume.dhall
}
