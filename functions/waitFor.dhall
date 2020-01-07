    \(hostname : Text)
->  \(port : Natural)
->  let test =
              "python -c '"
          ++  "import socket, sys; "
          ++  "socket.socket(socket.AF_INET, socket.SOCK_STREAM)"
          ++  ".connect((sys.argv[1], ${Natural/show port}))' ${hostname}"

    let debug = "waiting for ${hostname}:${Natural/show port}"

    in  [ "sh"
        , "-c"
        , "until ${test} 2>/dev/null; do echo '${debug}'; sleep 1; done"
        ]
