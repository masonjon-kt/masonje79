#!/bin/sh
#set -x

docker -H unix:///run/user/500/docker.sock "$@"
