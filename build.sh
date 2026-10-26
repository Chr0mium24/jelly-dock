#!/bin/sh
# 编译成单个可执行文件 ./jelly-dock
set -e
cd "$(dirname "$0")"
swiftc -O main.swift -o jelly-dock
