#!/bin/bash
#D/L from github

git clone https://github.com/google/google-api-cpp-client.git

cd google-api-cpp-client/service_apis
DOWNLOAD="curl -J -O"
$DOWNLOAD https://developers.google.com/resources/api-libraries/download/bigquery/v2/cpp
$DOWNLOAD https://developers.google.com/resources/api-libraries/download/storage/v1/cpp
#get others
# APIS: https://developers.google.com/apis-explorer/#p/
#unpack
for file in *.zip; do
  unzip $file
done
cd ..

./prepare_dependencies.py
mkdir build && cd build
# still need lines to install additional dependancies
../external_dependencies/install/bin/cmake -Dgoogleapis_build_mongoose:BOOL=ON -Dgoogleapis_build_samples:BOOL=ON -Dgoogleapis_build_service_apis:BOOL=ON -Dgoogleapis_build_tests:BOOL=ON -Dgflags_DIR:PATH=~/gflags/build -Dcurl_DIR:PATH=../external_dependencies/curl-7.42.1 ..
# this can fail the second time around
make all
make test
make install


