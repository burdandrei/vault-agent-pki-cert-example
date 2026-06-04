#!/bin/bash
set -e
SOURCE_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SOURCE_PATH

#chmod -R 777 $PWD/mydatapower

#podman machine stop
#podman machine set --memory 8192
#podman machine start

#podman run --privileged --user root -it --platform linux/amd64 \
docker rm my-datapower --force || true
docker run --privileged --user root --platform linux/amd64 \
  --name my-datapower \
  -e DATAPOWER_ACCEPT_LICENSE="true" \
  -e DATAPOWER_INTERACTIVE="true" \
  -e DATAPOWER_WORKER_THREADS=2 \
  -p 9090:9090 \
  -p 5550:5550 \
  -p 5554:5554 \
  -p 8043:8043 \
  -v ${PWD}/config:/opt/ibm/datapower/drouter/config \
  -v ${PWD}/local:/opt/ibm/datapower/drouter/local \
  -v ${PWD}/certs:/opt/ibm/datapower/root/secure/usrcerts \
  icr.io/cpopen/datapower/datapower-limited:11.0.0.1

echo "Web UI: https://localhost:9090"
echo "SOMA API (SOAP)): https://localhost:5550"
echo "ROMA API (Rest)): https://localhost:5554"
echo "TLS Demo Service (empty response): https://localhost:8043"
echo "User/pass: admin/admin"
echo "DP keystore obj: ssl-keystore"
echo "DP keystore obj: ssl-keystore"
echo "DP key obj: demo"
echo "DP cert obj: demo"
echo "DP key file: demo-privkey.pem"
echo "DP cert file: demo-sscert.pem"
echo "Key and Cert files store in cert:/// + local://"
echo "Current referent from key and cert obj is to cert:///"
