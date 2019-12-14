{ name : Text
, type : ./ServiceType.dhall
, privileged : Bool
, ports : Optional (List ./Port.dhall)
, container : ./Container.dhall
, init-containers : Optional (List ./Container.dhall)
}
