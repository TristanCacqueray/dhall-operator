{ Type = ../types/Application.dhall
, default =
    { kind = "app"
    , environs =
            \(serviceType : ../types/ServiceType.dhall)
        ->  [] : List ../types/Env.dhall
    , volumes =
            \(serviceType : ../types/ServiceType.dhall)
        ->  [] : List ../types/Volume.dhall
    }
}
