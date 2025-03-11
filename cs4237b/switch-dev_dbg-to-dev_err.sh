#!/bin/bash
find . -type f -exec sed -i 's/dev_dbg/dev_err/g' {} +
