#!/usr/bin/env bash

yad --width=400 --height=200 \
    --title="YAD mit Tabs" \
    --notebook \
    --tab="Erster Tab" \
    --form --field="Name:" --field="Alter:" "" "" \
    --tab="Zweiter Tab" \
    --form --field="Land:" --field="Stadt:" "" ""
