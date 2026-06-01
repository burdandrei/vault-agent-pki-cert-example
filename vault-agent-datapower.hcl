pid_file = "./pidfile"

vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method {
     type = "token_file"

    config = {
      token_file_path = ".vault-token"
    }
  }

}

template {
  source = "source.vtmpl"
  destination = "destination"
  command = "bash -c 'curl -k -u admin:admin -X PUT https://datapower-host:5554/mgmt/filestore/default/cert/cert.pem -T certs/cert.pem && curl -k -u admin:admin -X PUT https://datapower-host:5554/mgmt/filestore/default/cert/cert.key -T certs/cert.key && curl -k -u admin:admin -X PUT https://datapower-host:5554/mgmt/filestore/default/cert/ca.pem -T certs/ca.pem && echo \"Certificate updated on DataPower successfully!\"'"
}