#!/usr/bin/env bash

while read package; do
    cp ${package} ./dist/lib/
done < packages.txt
