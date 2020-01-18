(../schemas/Application.dhall)::{
, name = "demo"
, services =
  [ (../schemas/Service.dhall)::{
    , name = "postgres"
    , ports = Some
        [ (../schemas/Port.dhall)::{ container = 5432, name = "pg" } ]
    , container = (../schemas/Container.dhall)::{
      , image = "docker.io/library/postgres:12.1"
      }
    }
  , (../schemas/Service.dhall)::{
    , name = "worker"
    , container = (../schemas/Container.dhall)::{
      , image = "registry.fedoraproject.org/fedora:31"
      , command = Some
          [ "sh"
          , "-c"
          ,     "python3 -c '"
            ++  "import socket, sys; "
            ++  "socket.socket(socket.AF_INET, socket.SOCK_STREAM)"
            ++  ".connect((sys.argv[1], 5432))' postgres &&"
            ++  "echo Connected && sleep infinity"
          ]
      }
    }
  ]
}
