{ Schemas =
    { Application = ./schemas/Application.dhall
    , Service = ./schemas/Service.dhall
    , Container = ./schemas/Container.dhall
    , Port = ./schemas/Port.dhall
    , Volume = ./schemas/Volume.dhall
    }
, Types =
    { Env = ./types/Env.dhall
    , EnvSecret = ./types/EnvSecret.dhall
    , Service = ./types/Service.dhall
    , ServiceType = ./types/ServiceType.dhall
    , Volume = ./types/Volume.dhall
    , File = ./types/File.dhall
    }
, Functions =
    { waitFor = ./functions/waitFor.dhall
    , getCommand = ./functions/getCommand.dhall
    }
}
