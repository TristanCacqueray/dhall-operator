    \(serviceType : ../types/ServiceType.dhall)
->  merge
      { _All = "_all"
      , Config = "config"
      , Database = "db"
      , Launcher = "launcher"
      , Scheduler = "scheduler"
      , Executor = "executor"
      , Worker = "worker"
      , Gateway = "gateway"
      , Other = "other"
      }
      serviceType
