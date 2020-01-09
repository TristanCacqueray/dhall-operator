{ name : Text
, kind : Text
, services : List ./Service.dhall
, environs : forall (serviceType : ./ServiceType.dhall) -> List ./Env.dhall
, volumes : forall (serviceType : ./ServiceType.dhall) -> List ./Volume.dhall
, secrets : forall (serviceType : ./ServiceType.dhall) -> List ./Volume.dhall
, env-secrets :
    forall (serviceType : ./ServiceType.dhall) -> List ./EnvSecret.dhall
}
