    \(serviceType : ../types/ServiceType)
->  merge
      { _All = "_all"
      , Config = "config"
      , Database = "db"
      , Scheduler = "scheduler"
      , Executor = "executor"
      , Worker = "worker"
      , Gateway = "gateway"
      , Other = "other"
      }
      serviceType
