#!/bin/bash
cp ../diagram.png .
line=$(grep -n 'MARKDOWN' pre-index.html | cut -d ":" -f 1)
{ head -n $(($line-1)) pre-index.html; cat ../README.md; tail -n +$((line+1)) \
    pre-index.html; } > index.html
