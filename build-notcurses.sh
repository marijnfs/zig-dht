#!/bin/bash

git submodule update --init
mkdir -p ext/notcurses/build
pushd ext/notcurses/build
cmake -DUSE_DOCTEST:BOOL="0" -DUSE_CPP:BOOL="0" -DUSE_CXX:BOOL="0" -DUSE_DEFLATE:BOOL="0" -DUSE_PANDOC:BOOL="0" -DUSE_POC:BOOL="0" -D USE_STATIC:BOOL="0" -DUSE_MULTIMEDIA:STRING="none" -DBUILD_FFI_LIBRARY:BOOL="0" -DBUILD_EXECUTABLES:BOOL="0" -DBUILD_TESTING:BOOL="0" ..
make -j
sudo make install
popd
