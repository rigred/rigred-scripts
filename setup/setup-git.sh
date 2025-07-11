#!/usr/bin/env bash
git config commit.template "$(git rev-parse --show-toplevel)/.gitmessage"
git config core.commentChar ';'
echo "✔ Git commit template & commentChar configured."
