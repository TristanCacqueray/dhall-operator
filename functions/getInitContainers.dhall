let Container = ../types/Container.dhall

let get
    : forall (containers : Optional (List Container)) -> List Container
    =     \(containers : Optional (List Container))
      ->  Optional/fold
            (List Container)
            containers
            (List Container)
            (\(some : List Container) -> some)
            ([] : List Container)

in  get
