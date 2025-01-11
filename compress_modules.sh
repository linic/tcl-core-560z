#!/bin/bash

find . -type f -name "*.ko" | while read -r file; do
    dir=$(dirname "$file")
    base=$(basename "$file" .ko)
    gzip -9 -c "$file" > "$dir/$base.ko.gz"
    advdef -z4 "$dir/$base.ko.gz"
    rm "$file"
done
