let getCommand
    : forall (container : ../types/Container.dhall) -> List Text
    =     \(container : ../types/Container.dhall)
      ->  Optional/fold
            (List Text)
            container.command
            (List Text)
            (\(some : List Text) -> some)
            ([] : List Text)

in  getCommand
