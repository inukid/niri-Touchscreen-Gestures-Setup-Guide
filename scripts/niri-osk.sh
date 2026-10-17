#!/usr/bin/env bash
if pgrep -x squeekboard > /dev/null; then
    pkill squeekboard
else
    squeekboard &
fi
