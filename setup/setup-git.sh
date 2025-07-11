#!/usr/bin/env bash
git config commit.template "$(git rev-parse --show-toplevel)/.gitmessage"
echo "✔ Git commit template configured."
