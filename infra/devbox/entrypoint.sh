#!/bin/sh
set -eu

mkdir -p "$HOME" /data/t3code
exec t3 serve --base-dir /data/t3code
