#!/bin/bash
# find the line number of 'MARKDOWN'
line=$(grep -n 'MARKDOWN' pre-index.html | cut -d ":" -f 1)
# insert the README.md in the proper spot of the index.html file
{ head -n $(($line-1)) pre-index.html; cat ../README.md; tail -n +$((line+1)) \
    pre-index.html; } > index.html
