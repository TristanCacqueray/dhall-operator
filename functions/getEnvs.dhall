let Env = ../types/Env.dhall

let getEnv
    : forall (envs : Optional (List Env)) -> List ../types/Env.dhall
    =     \(envs : Optional (List Env))
      ->  Optional/fold
            (List Env)
            envs
            (List Env)
            (\(some : List Env) -> some)
            ([] : List Env)

in  getEnv
