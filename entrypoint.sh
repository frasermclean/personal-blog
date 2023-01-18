#!/bin/sh
set -e
service ssh start
exec apache2-foreground