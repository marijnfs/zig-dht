#!/bin/bash

mkdir -p ext/notcurses/build
pushd ext/notcurses/build
cmake -DUSE_DOCTEST:BOOL="0" -DUSE_CPP:BOOL="0" -DUSE_PANDOC:BOOL="0" -DUSE_POC:BOOL="0" -DUSE_MULTIMEDIA:STRING="none" ..
make -j
popd
