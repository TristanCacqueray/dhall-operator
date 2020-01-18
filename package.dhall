{ Schemas =
    { Application = ./schemas/Application.dhall
    , Env = ./schemas/Env.dhall
    , EnvSecret = ./schemas/EnvSecret.dhall
    , File = ./schemas/File.dhall
    , Service = ./schemas/Service.dhall
    , Container = ./schemas/Container.dhall
    , Port = ./schemas/Port.dhall
    , Volume = ./schemas/Volume.dhall
    }
, Types = { ServiceType = ./types/ServiceType.dhall }
, Functions =
    { waitFor = ./functions/waitFor.dhall
    , getCommand = ./functions/getCommand.dhall
    , getInitContainers = ./functions/getInitContainers.dhall
    }
}
