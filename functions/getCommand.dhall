let getCommand
    : forall (container : ../types/Container.dhall) -> List Text
    =     \(container : ../types/Container.dhall)
      ->  Optional/fold
            (List Text)
            container.command
            (List Text)
            ( (../Prelude.dhall).List.map
                Text
                Text
                (\(some : Text) -> "\"" ++ some ++ "\"")
            )
            ([] : List Text)

in  getCommand
