let getCommandQuoted
    : forall (container : ../types/Container.dhall) -> List Text
    =     \(container : ../types/Container.dhall)
      ->  (../Prelude.dhall).List.map
            Text
            Text
            (\(some : Text) -> "\"" ++ some ++ "\"")
            (./getCommand.dhall container)

in  getCommandQuoted
